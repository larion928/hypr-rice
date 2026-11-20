"""The running kernel still has its modules: after a kernel update without a reboot it has not."""
from ..model import Finding, Severity

TITLE = "Ядро"


def detect(ctx):
    modules = ctx.path(f"/usr/lib/modules/{ctx.kernel_release}")
    if modules.is_dir():
        return []
    return [Finding(key="kernel:modules", severity=Severity.PROBLEM,
                    text=f"ядро {ctx.kernel_release} обновлено, а машина не перезагружена: его модулей больше нет",
                    evidence=(f"нет каталога {modules}",),
                    hint="перезагрузись: до этого не подключатся USB-устройства, сеть и звук, которым нужен модуль")]
