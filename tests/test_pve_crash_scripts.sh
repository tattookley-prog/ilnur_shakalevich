#!/usr/bin/env bash
#
# Безопасные (safe) тесты для pve-crash-with-reboot.sh и
# pve-crash-no-reboot.sh.
#
# Эти тесты НЕ вызывают панику ядра и НЕ требуют реального Proxmox VE.
# Они проверяют только:
#   - обработку аргументов командной строки;
#   - обязательную проверку прав root (ожидается отказ при запуске без root,
#     что и происходит в CI/тестовом окружении);
#   - наличие обязательных защитных настроек в исходном коде скриптов
#     (set -Eeuo pipefail, фиксированный PATH, LC_ALL=C).
#
# Скрипты НИКОГДА не должны запускаться с --execute в тестовом окружении.
#
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WITH_REBOOT="${SCRIPT_DIR}/pve-crash-with-reboot.sh"
NO_REBOOT="${SCRIPT_DIR}/pve-crash-no-reboot.sh"

FAILURES=0

assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local desc="$3"
    if [[ "${actual}" -ne "${expected}" ]]; then
        echo "FAIL: ${desc} (ожидался код выхода ${expected}, получен ${actual})"
        FAILURES=$((FAILURES + 1))
    else
        echo "OK:   ${desc}"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local desc="$3"
    if [[ "${haystack}" != *"${needle}"* ]]; then
        echo "FAIL: ${desc} (в выводе не найдено: '${needle}')"
        FAILURES=$((FAILURES + 1))
    else
        echo "OK:   ${desc}"
    fi
}

for script in "${WITH_REBOOT}" "${NO_REBOOT}"; do
    name="$(basename "${script}")"

    # 1. Скрипт существует и исполняемый.
    if [[ ! -x "${script}" ]]; then
        echo "FAIL: ${name} должен существовать и быть исполняемым"
        FAILURES=$((FAILURES + 1))
        continue
    fi

    # 2. bash -n (проверка синтаксиса).
    if ! bash -n "${script}"; then
        echo "FAIL: ${name} не проходит проверку синтаксиса (bash -n)"
        FAILURES=$((FAILURES + 1))
    else
        echo "OK:   ${name} проходит проверку синтаксиса (bash -n)"
    fi

    # 3. Обязательные защитные настройки присутствуют в коде.
    assert_contains "$(cat "${script}")" "set -Eeuo pipefail" \
        "${name}: содержит 'set -Eeuo pipefail'"
    assert_contains "$(cat "${script}")" "PATH=/usr/sbin:/usr/bin:/sbin:/bin" \
        "${name}: содержит фиксированный PATH"
    assert_contains "$(cat "${script}")" "LC_ALL=C" \
        "${name}: содержит LC_ALL=C"
    assert_contains "$(cat "${script}")" "systemd-detect-virt --container --quiet" \
        "${name}: проверяет и отклоняет контейнеры"
    assert_contains "$(cat "${script}")" "systemd-detect-virt --vm" \
        "${name}: требует положительного обнаружения ВМ"

    # 4. Слишком много аргументов отклоняется (код выхода 2).
    set +e
    out="$("${script}" a b 2>&1)"
    code=$?
    set -e
    assert_exit_code 2 "${code}" "${name}: отклоняет более одного аргумента"

    # 5. Неверный (единственный) аргумент отклоняется (код выхода 2).
    set +e
    out="$("${script}" --bogus 2>&1)"
    code=$?
    set -e
    assert_exit_code 2 "${code}" "${name}: отклоняет неизвестный аргумент"
    assert_contains "${out}" "Использование" "${name}: печатает справку по использованию"

    # 6. Без root (текущее тестовое окружение НЕ root) должен произойти отказ
    #    независимо от режима (--dry-run по умолчанию, либо явно указанный).
    if [[ "$(id -u)" -eq 0 ]]; then
        echo "SKIP: тесты проверки root пропущены (тесты запущены от имени root)"
    else
        for mode_args in "" "--dry-run" "--execute"; do
            # shellcheck disable=SC2086
            set +e
            out="$("${script}" ${mode_args} </dev/null 2>&1)"
            code=$?
            set -e
            assert_exit_code 1 "${code}" "${name}: отклоняет запуск без root (аргументы: '${mode_args}')"
            assert_contains "${out}" "root" "${name}: сообщение об ошибке упоминает root (аргументы: '${mode_args}')"
        done
    fi
done

echo
if [[ "${FAILURES}" -ne 0 ]]; then
    echo "ИТОГ: ${FAILURES} тест(ов) провалено."
    exit 1
fi

echo "ИТОГ: все тесты пройдены успешно."
