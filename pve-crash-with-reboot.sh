#!/usr/bin/env bash
set -Eeuo pipefail

export PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
export LC_ALL=C

usage() {
    printf 'Использование: %s [--dry-run|--execute]\n' "$0"
}

mode="${1:---dry-run}"
if [[ $# -gt 1 || ( "$mode" != '--dry-run' && "$mode" != '--execute' ) ]]; then
    usage >&2
    exit 2
fi

die() {
    printf 'Ошибка: %s\n' "$*" >&2
    exit 1
}

[[ $EUID -eq 0 ]] || die 'скрипт должен быть запущен от root.'
for command in pveversion systemd-detect-virt hostname sleep; do
    command -v "$command" >/dev/null 2>&1 ||
        die "не найдена команда: $command"
done

if systemd-detect-virt --container >/dev/null 2>&1; then
    die 'контейнерная среда запрещена.'
fi
systemd-detect-virt --vm >/dev/null 2>&1 ||
    die 'скрипт должен выполняться внутри виртуальной машины.'

[[ -w /proc/sysrq-trigger ]] ||
    die '/proc/sysrq-trigger недоступен для записи.'
[[ -w /proc/sys/kernel/panic ]] ||
    die '/proc/sys/kernel/panic недоступен для записи.'

host_name=$(hostname)
virtualization=$(systemd-detect-virt)
pve_version=$(pveversion) || die 'не удалось получить версию Proxmox VE.'

printf 'Имя узла: %s\n' "$host_name"
printf 'Виртуализация: %s\n' "$virtualization"
printf 'Версия Proxmox VE: %s\n' "$pve_version"
printf '\nВНИМАНИЕ: это тест преднамеренной паники ядра и немедленно прервет работу этого узла.\n'
printf 'ВНИМАНИЕ: убедитесь через консоль внешнего гипервизора, что это нужная вложенная VM.\n'
printf 'Обнаружение VM само по себе не подтверждает правильность вложенности.\n'
printf 'Таймер panic=10 автоматически перезагрузит узел после паники; резервные копии не создаются.\n'

if [[ "$mode" == '--dry-run' ]]; then
    printf '\nСухой прогон: записи в /proc и вызов паники НЕ выполнялись.\n'
    exit 0
fi

[[ -t 0 ]] || die 'режим --execute требует интерактивный stdin.'
printf '\nДля продолжения введите ровно «CRASH WITH REBOOT»: '
read -r confirmation
[[ "$confirmation" == 'CRASH WITH REBOOT' ]] ||
    die 'подтверждение не совпало; паника не вызвана.'

printf 'Устанавливается автоматическая перезагрузка через 10 секунд...\n'
printf '10\n' > /proc/sys/kernel/panic
sleep 1
printf 'c\n' > /proc/sysrq-trigger
