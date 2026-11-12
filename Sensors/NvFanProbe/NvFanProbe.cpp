/*
 * NvFanProbe / RogSensors —— 传感器补丁 kext
 *
 * 为什么需要它：
 *   macOS 26 起，AppleSMC 的用户态私有接口对第三方进程一律返回
 *   kIOReturnBadArgument（selector / 打开类型 / 结构体尺寸全部试过均不通），
 *   VirtualSMC 的 SMCProcessor 插件在这台机器上也没有挂载，
 *   所以温度、风扇在用户态拿不到，只能在内核层读。
 *
 * 本 kext 做的事：
 *   1) 通过 MSR IA32_PACKAGE_THERM_STATUS (0x1B1) + IA32_TEMPERATURE_TARGET (0x1A2)
 *      计算 CPU 封装温度，每秒刷新一次；
 *   2) 通过 RAPL (0x615 能量单位 / 0x611 PKG_ENERGY_STATUS / 0x619 DRAM_ENERGY_STATUS)
 *      计算 CPU 封装功耗与内存功耗（毫瓦，每秒差分）；
 *   3) 把结果以 IORegistry 属性形式发布（CPUTempC / CPUPowerMW / DRAMPowerMW /
 *      TjMax / Heartbeat），用户态用 IOServiceGetMatchingService("NvFanProbe")
 *      直接读取，无需 root。
 */

#include <IOKit/IOService.h>
#include <IOKit/IOLib.h>
#include <IOKit/IOWorkLoop.h>
#include <IOKit/IOTimerEventSource.h>

#define super IOService

#define kMSRTjMax       0x1A2   // IA32_TEMPERATURE_TARGET
#define kMSRPkgTherm    0x1B1   // IA32_PACKAGE_THERM_STATUS
#define kMSRThermStatus 0x19C   // IA32_THERM_STATUS（核心级，包级无效时兜底）
#define kMSRRaplUnit    0x615   // MSR_RAPL_POWER_UNIT
#define kMSRPkgEnergy   0x611   // MSR_PKG_ENERGY_STATUS
#define kMSRDrumEnergy  0x619   // MSR_DRAM_ENERGY_STATUS
#define kRefreshMS      1000

#include <mach/mach_time.h>

static inline uint64_t msSinceBoot()
{
    // 本 kext 仅 x86_64：Intel 平台 mach 绝对时间的 timebase 恒为 1:1（纳秒）
    return mach_absolute_time() / 1000000ULL;
}

static inline uint64_t rgReadMSR(uint32_t msr)
{
    uint32_t lo = 0, hi = 0;
    __asm__ __volatile__("rdmsr" : "=a"(lo), "=d"(hi) : "c"(msr));
    return ((uint64_t)hi << 32) | lo;
}

// RAPL 能量计数器为 32 位循环，回绕时补上 2^32
static inline uint64_t energyDelta(uint32_t cur, uint32_t prev)
{
    return cur >= prev ? (uint64_t)(cur - prev)
                       : (uint64_t)(cur + (0xFFFFFFFFu - prev) + 1);
}

class NvFanProbe : public IOService
{
    OSDeclareDefaultStructors(NvFanProbe)

public:
    virtual bool start(IOService *provider) APPLE_KEXT_OVERRIDE;
    virtual void stop(IOService *provider) APPLE_KEXT_OVERRIDE;
    virtual void free() APPLE_KEXT_OVERRIDE;

    void tick();

private:
    IOWorkLoop          *fLoop  = nullptr;
    IOTimerEventSource  *fTimer = nullptr;
    uint32_t             fTjMax = 100;
    uint32_t             fBeat  = 0;
    bool                 fSrcSet = false;
    // RAPL
    double               fEnergyUnit = 1.0 / 65536.0;  // 焦耳/计数，0x615 bits12:8
    bool                 fHasDram = false;             // 0x619 是否可读
    uint32_t             fPrevPkg = 0;
    uint32_t             fPrevDram = 0;
    bool                 fFirstEnergy = true;
    uint64_t             fLastPeriodMS = 0;            // 上次采样时刻（mtime）
};

OSDefineMetaClassAndStructors(NvFanProbe, IOService)

bool NvFanProbe::start(IOService *provider)
{
    if (!super::start(provider)) return false;

    // TjMax：MSR 0x1A2 bit 23:16，单位摄氏度
    uint32_t tj = (uint32_t)((rgReadMSR(kMSRTjMax) >> 16) & 0xFF);
    if (tj < 50 || tj > 130) tj = 100;
    fTjMax = tj;

    setProperty("TjMax", fTjMax, 32);
    setProperty("CPUTempC", (unsigned int)0, 32);
    setProperty("CPUPowerMW", (unsigned long long)0, 64);
    setProperty("Source", "MSR-0x1B1");

    // RAPL 能量单位（0x615 bits12:8）：能量 = 1/2^EU 焦耳
    // 先用 CPUID leaf 6 ECX bit14 确认平台支持 RAPL，再读 0x615/0x611/0x619，
    // 避免在不支持的平台上 rdmsr 触发 #GP
    uint32_t eax = 0, ebx = 0, ecx = 0, edx = 0;
    __asm__ __volatile__("cpuid" : "=a"(eax), "=b"(ebx), "=c"(ecx), "=d"(edx) : "a"(6));
    if (ecx & (1U << 14)) {
        uint64_t unit = rgReadMSR(kMSRRaplUnit);
        uint32_t eu = (uint32_t)((unit >> 8) & 0x1F);
        if (eu >= 1 && eu <= 20) fEnergyUnit = 1.0 / (double)(1ULL << eu);
        fHasDram = true;
        setProperty("RAPL", "enabled");
    } else {
        setProperty("RAPL", "unsupported");
    }

    fLoop = IOWorkLoop::workLoop();
    if (fLoop) {
        fTimer = IOTimerEventSource::timerEventSource(
            this,
            OSMemberFunctionCast(IOTimerEventSource::Action, this, &NvFanProbe::tick));
        if (fTimer && fLoop->addEventSource(fTimer) == kIOReturnSuccess) {
            fTimer->setTimeoutMS(500);
        }
    }

    IOLog("NvFanProbe: started, TjMax=%u\n", fTjMax);

    // 必须显式注册：0.4 版没调 registerService()，服务保持 !registered 状态，
    // IOServiceGetMatchingServices 全部匹配不到（用户态只能按路径兜底读取）。
    registerService();

    return true;
}

void NvFanProbe::tick()
{
    // 优先包级热状态（0x1B1），失败再退到核心级（0x19C）
    uint64_t v = rgReadMSR(kMSRPkgTherm);
    const char *src = "MSR-0x1B1";

    if (!(v & 0x80000000ULL)) {
        v = rgReadMSR(kMSRThermStatus);
        src = "MSR-0x19C";
    }

    // bit31 = reading valid；bit22:16 = 距 TjMax 的读数（°C）
    if (v & 0x80000000ULL) {
        int32_t readout = (int32_t)((v >> 16) & 0x7F);
        int32_t temp = (int32_t)fTjMax - readout;
        if (temp >= 0 && temp <= 130) {
            setProperty("CPUTempC", (unsigned int)temp, 32);
            if (!fSrcSet) { setProperty("Source", src); fSrcSet = true; }
        }
    }

    setProperty("Heartbeat", (unsigned int)(fBeat++), 32);

    // RAPL 功耗：能量计数器差分 / 间隔时间，发布毫瓦（64 位整数保留精度）
    if (fHasDram) {
        uint64_t nowMS = msSinceBoot();
        uint64_t dms = (fLastPeriodMS > 0 && nowMS > fLastPeriodMS) ? nowMS - fLastPeriodMS : 0;

        if (dms > 50 && dms < 10000) {
            double sec = (double)dms / 1000.0;
            uint32_t pkg = (uint32_t)(rgReadMSR(kMSRPkgEnergy) & 0xFFFFFFFFULL);
            if (!fFirstEnergy) {
                double w = (double)energyDelta(pkg, fPrevPkg) * fEnergyUnit / sec;
                if (w >= 0.0 && w < 500.0)
                    setProperty("CPUPowerMW", (unsigned long long)(w * 1000.0), 64);
            }
            fPrevPkg = pkg;

            // DRAM 能量寄存器（0x619）：客户端平台常读出恒 0，按 0 处理
            uint32_t dram = (uint32_t)(rgReadMSR(kMSRDrumEnergy) & 0xFFFFFFFFULL);
            if (!fFirstEnergy) {
                double dw = (double)energyDelta(dram, fPrevDram) * fEnergyUnit / sec;
                if (dw >= 0.0 && dw < 200.0)
                    setProperty("DRAMPowerMW", (unsigned long long)(dw * 1000.0), 64);
            }
            fPrevDram = dram;
            fFirstEnergy = false;
        }
        fLastPeriodMS = nowMS;
    }

    if (fTimer) fTimer->setTimeoutMS(kRefreshMS);
}

void NvFanProbe::stop(IOService *provider)
{
    if (fTimer) {
        fTimer->cancelTimeout();
        if (fLoop) fLoop->removeEventSource(fTimer);
        fTimer->release();
        fTimer = nullptr;
    }
    if (fLoop) {
        fLoop->release();
        fLoop = nullptr;
    }
    super::stop(provider);
}

void NvFanProbe::free()
{
    super::free();
}

// 现代 ld 不再自动生成 kext 的 kmod_info 符号，需显式声明，
// 否则 kmutil 会报 "kexts must have a _kmod_info symbol"。
//
// 注意：第 3/4 个参数不能为 0 —— 内核靠 kmod 的 start 回调进入 kext 的
// 模块初始化流程，传 0 会导致 OSMetaClass 不注册，表现是 kext 加载成功、
// 但 IOService 实例永远为 0、personality 永不匹配。
// 也不能直接链 libkmod.a（它的 _start 依赖内核私有符号 __realmain，
// 第三方 kext 在链接期会报 "could not find a kext which exports this symbol"）。
extern "C" {
#include <mach/kmod.h>

static kern_return_t NvFanProbeKernStart(kmod_info_t *ki, void *data)
{
    return KERN_SUCCESS;
}

static kern_return_t NvFanProbeKernStop(kmod_info_t *ki, void *data)
{
    return KERN_SUCCESS;
}
}

KMOD_EXPLICIT_DECL(com.yangjp.NvFanProbe, "0.5", NvFanProbeKernStart, NvFanProbeKernStop)

