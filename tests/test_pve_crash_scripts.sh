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

# --- Дополнительные тесты (только при наличии passwordless sudo) --------
# Эти тесты запускают скрипты от root через sudo, чтобы проверить полный
# путь --dry-run (вывод цели) и путь --execute с ЗАВЕДОМО НЕВЕРНОЙ фразой
# подтверждения (что гарантированно останавливает скрипт ДО записи в
# /proc и ДО вызова паники ядра). Реальная паника ядра НИКОГДА не
# вызывается этими тестами.
if [[ "$(id -u)" -ne 0 ]] && command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    FAKE_PVEVERSION=/usr/sbin/pveversion
    if [[ -e "${FAKE_PVEVERSION}" ]]; then
        echo "SKIP: расширенные тесты через sudo пропущены (pveversion уже существует в системе)"
    else
        cleanup_fake_pveversion() {
            sudo rm -f "${FAKE_PVEVERSION}"
        }
        trap cleanup_fake_pveversion EXIT

        sudo tee "${FAKE_PVEVERSION}" >/dev/null <<'EOF'
#!/bin/bash
echo "pve-manager/8.0.3/test (running kernel: 6.2.16-3-pve)"
EOF
        sudo chmod +x "${FAKE_PVEVERSION}"

        for script in "${WITH_REBOOT}" "${NO_REBOOT}"; do
            name="$(basename "${script}")"

            # --dry-run как root: должен вывести полную информацию о цели
            # и завершиться с кодом 0, ничего не изменяя.
            set +e
            out="$(sudo "${script}" --dry-run 2>&1)"
            code=$?
            set -e
            assert_exit_code 0 "${code}" "${name}: --dry-run от root завершается успешно"
            assert_contains "${out}" "Режим --dry-run" "${name}: --dry-run от root печатает сообщение о выходе без изменений"
            assert_contains "${out}" "Резервная копия данных НЕ создаётся" "${name}: --dry-run от root печатает предупреждение об отсутствии резервной копии"

            # --execute при неинтерактивном stdin (пайп): должен остановиться
            # ДО запроса подтверждения, ДО записи в /proc и ДО паники ядра.
            set +e
            out="$(echo "неверная фраза" | sudo "${script}" --execute 2>&1)"
            code=$?
            set -e
            assert_exit_code 1 "${code}" "${name}: --execute с неинтерактивным stdin отклоняется"
            assert_contains "${out}" "интерактивного stdin" "${name}: --execute сообщает о требовании интерактивного stdin"
        done

        trap - EXIT
        cleanup_fake_pveversion
    fi
else
    echo "SKIP: расширенные тесты через sudo пропущены (root или passwordless sudo недоступны)"
fi

echo
if [[ "${FAILURES}" -ne 0 ]]; then
    echo "ИТОГ: ${FAILURES} тест(ов) провалено."
    exit 1
fi

echo "ИТОГ: все тесты пройдены успешно."
