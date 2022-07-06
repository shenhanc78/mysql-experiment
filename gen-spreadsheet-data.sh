#!/bin/bash

set -ue
set -o pipefail

ddir="$(cd "$(dirname "$0")" ; pwd)"

declare -a pairs=( $* )
declare -a benchmarks=( select_random_ranges oltp_delete oltp_read_only oltp_read_write oltp_update_index )

function gen_pair() {
    local -r p="$1"
    local -r base="$(echo "$p" | sed -nEe 's!(.*)-vs-.*!\1!p')"-mysql
    local -r test="$(echo "$p" | sed -nEe 's!.*-vs-(.*)!\1!p')"-mysql
    local -a result=( "$p " )
    for bm in "${benchmarks[@]}"; do
        local log="sysbench.${p}.${bm}.result"
        ${ddir}/t-test ${base}/sysbench.${bm}.result ${test}/sysbench.${bm}.result 1>"$log" 2>&1
        if grep -F "Difference is not significant." "$log" 1>/dev/null 2>&1 ; then
            result+=( " not significant " )
        else
            result+=( " $(sed -nEe 's!^Percent\s+\(95% CI\) = (.*)$!\1!p' "$log") " )
        fi
        rm -f "$log"
    done
    IFS="|" ; echo "${result[*]}"
}

IFS="|" ; echo "p / b | ${benchmarks[*]} "

for p in "${pairs[@]}"; do
    if [[ "$p" == "SEPARATOR" ]]; then
        echo
        IFS="|" ; echo "p / b | ${benchmarks[*]} "
    else
        gen_pair "$p"
    fi
done

cat <<EOF
!json:UpdateSpreadsheetPropertiesRequest{"fields": "title", "properties": {"title": "MySql Experiment"}}
!json:UpdateSheetPropertiesRequest{"fields": "title", "properties": {"sheetId": 1, "title": "MySql performance numbers"}}
!json:RepeatCellRequest{"range": {"sheetId": 1, "startRowIndex": 0, "startColumnIndex": 0}, "fields":"userEnteredFormat.textFormat.fontSize,userEnteredFormat.verticalAlignment,userEnteredFormat.horizontalAlignment", "cell": {"userEnteredFormat": {"verticalAlignment": "MIDDLE", "horizontalAlignment": "CENTER", "textFormat": {"fontSize": 14}}}}
!json:UpdateDimensionPropertiesRequest{"fields":"pixelSize", "range": {"dimension": "COLUMNS", "sheetId": 1, "startIndex": 0, "endIndex": 1},"properties": {"pixelSize": 400}}
!json:UpdateDimensionPropertiesRequest{"fields":"pixelSize", "range": {"dimension": "COLUMNS", "sheetId": 1, "startIndex": 1, "endIndex": 6},"properties": {"pixelSize": 350}}
EOF
