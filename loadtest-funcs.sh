#!/bin/bash

function setup_mysql() {
  local -r mysql_dir="$1"
  echo "Setup in directory: ${mysql_dir} ... "
  cat <<EOF > "${mysql_dir}"/my.cnf
[client]
local-infile = 1
loose-local-infile = 1

[server]
local-infile = 1

[mysqld]
default-authentication-plugin=mysql_native_password
local-infile = 1
secure_file_priv = ''
EOF
  rm -fr "${mysql_dir}/install/data"
  "${mysql_dir}/install/bin/mysqld" \
      --defaults-file=${mysql_dir}/my.cnf --initialize-insecure --user=${USER}
  if [[ "$?" -ne 0 ]]; then echo "*** setup failed ***" ; return 1; fi
  return 0
}

function start_mysqld() {
  if kill "$(pgrep mysqld)" 1>/dev/null 2>&1 ; then
    sleep 5 # wait 10 seconds for the previous server to stop
  fi
  local -r mysql_dir="$1"
  echo "Starting mysqld in ${mysql_dir} ..."
  "${mysql_dir}/install/bin/mysqld" \
      --defaults-file=${mysql_dir}/my.cnf --user=$USER &
  echo "Sleeping 8 seconds to wait for server up ..." 
  sleep 8
}

function kill_prog_listening() {
  if [[ "$#" -ne "2" ]]; then echo "wrong number of arguments"; return 1; fi
  local -r prog="$1"
  local -r port="$2"
  local -r pid="$(netstat -lnp 2>/dev/null | sed -nEe "s/^tcp.*\s+:::${port}\s+.*LISTEN\s+([0-9]+)\/.+\$/\1/p")"
  if [[ $pid =~ ^[0-9]+$ ]]; then
    echo "Killing $prog (pid: $pid)"
    kill $pid
    return $?
  fi
}

function stop_mysqld() {
  kill_prog_listening mysqld 33060
  sleep 3
}

function load_dbt2_data_and_procedure() {
  set -xe
  [[ "$#" -eq 2 ]]
  local -r dbt2_source="$1"
  local -r mysql_dir="$2"
  local -r ddir="$(dirname "$dbt2_source")"
  ${dbt2_source}/scripts/mysql/mysql_load_db.sh \
    --path "${ddir}/dbt2-tool/data" \
    --local \
    --mysql-path "${mysql_dir}/install/bin/mysql --local-infile=1" \
    --host "127.0.0.1" \
    --user "root"

  ${dbt2_source}/scripts/mysql/mysql_load_sp.sh \
    --client-path "${mysql_dir}/install/bin" \
    --sp-path ${dbt2_source}/storedproc/mysql \
    --host "127.0.0.1" \
    --user "root"
}

function run_loadtest() {
  if [[ "$#" -ne "4" ]]; then
    echo "Wrong number of arguments."
    return 1
  fi
  local -r dbt2_source="$1"
  local -r output_base="$2"
  local -r run_time="$3"
  local -r client_lib="$4"
  local -r ddir="$(dirname "$dbt2_source")"
  if [[ -z "$output_base" ]]; then
    echo "Missing output_base argument"
    return 1
  fi
  set -x
  kill_prog_listening client 30000
  # --warehouses 30
  ${dbt2_source}/scripts/run_mysql.sh \
    --connections 20 --time ${run_time} \
    --warehouses 10 \
    --terminals 5 \
    --zero-delay \
    --host 127.0.0.1 \
    --user root --lib-client-path "$client_lib" \
    --output-base "$output_base"
  if [[ "$?" -ne "0" ]]; then
    echo "load test failed"
    return 1
  fi
  return 0
}

function move_file_with_version() {
    local -r origin="$1"
    local idx=1
    while [[ -e "${origin}.${idx}"  ]]; do
        ((++idx))
    done
    mv "$origin" "${origin}.${idx}"
}



# for sysbench
function setup_sysbench() {
  local -r mysql_dir="$1"
  local -r ddir="$(dirname "$mysql_dir")"
  echo "Setup in directory: ${mysql_dir} ... " ;
  setup_mysql "${mysql_dir}"
}

function run_sysbench_test() {
  local -r mysql_dir="$1"
  shift
  local -r test="$1"
  local -r iterations="$2"
  local -r table_size="$3"
  local -r event_number="$4"
  local -r additional_args="$5"
  local -r perfcounters="$6"
  local -r run_dir="${mysql_dir}/sysbench_runfiles"
  mkdir -p "$run_dir"
  sysbench "${test}" --table-size=${table_size} --num-threads=1 --rand-type=uniform --rand-seed=1 --db-driver=mysql \
    --mysql-db=sysbench --tables=1 --mysql-socket=/tmp/mysql.sock --mysql-user=root prepare
  {
    if [[ "${table_size}" -ge "1000000" ]]; then
      sysbench "${test}" --table-size=${table_size} --tables=1 --num-threads=1 --rand-type=uniform --rand-seed=1 --db-driver=mysql \
        --mysql-db=sysbench --mysql-socket=/tmp/mysql.sock --mysql-user=root prewarm
    fi
  }
  echo Running test: "${test}" ${iterations}x

  if [[ -n "$perfcounters" ]]; then
    echo "Invalid arguments."
    return 1
  fi

  if [[ "perfcounters" == "${perfcounters}" ]]; then
    return 1
    $(PERF_COMMAND) --pid "`pgrep -x $<`" --repeat 5 -- \
      sysbench "${test}" --table-size=${table_size} --tables=1 --num-threads=1 --rand-type=uniform --rand-seed=1 --db-driver=mysql \
        --events=${event_number} --time=0 --rate=0 ${additional_args} \
        --mysql-db=sysbench --mysql-socket=/tmp/mysql.sock --mysql-user=root run
  else
    for i in $(seq 1 $iterations); do
      sysbench "${test}" --table-size=${table_size} --tables=1 --num-threads=1 --rand-type=uniform --rand-seed=1 --db-driver=mysql \
        --events=${event_number} --time=0 --rate=0 ${additional_args} \
        --mysql-db=sysbench --mysql-socket=/tmp/mysql.sock --mysql-user=root run >& "${run_dir}"/"${test}".$i.log
    done
  fi

  sysbench "${test}" --table-size=${table_size} --tables=1 --num-threads=1 --rand-type=uniform --rand-seed=1 --db-driver=mysql \
    --mysql-db=sysbench --mysql-socket=/tmp/mysql.sock --mysql-user=root cleanup
}

function run_sysbench_loadtest() {
  local -r mysql_dir="$1"
  start_mysqld "$mysql_dir"
  "$mysql_dir"/install/bin/mysql -u root -e "DROP DATABASE IF EXISTS sysbench; CREATE DATABASE sysbench;"
  run_sysbench_test "$mysql_dir" oltp_read_write 8 5000 500
  run_sysbench_test "$mysql_dir" oltp_update_index 8 5000 500
  run_sysbench_test "$mysql_dir" oltp_delete 8 5000 500
  run_sysbench_test "$mysql_dir" select_random_ranges 8 5000 500
  run_sysbench_test "$mysql_dir" oltp_read_only 8 5000 500
  stop_mysqld
}

function run_sysbench_benchmark() {
  set -e
  local -r mysql_dir="$1"
  shift
  local -r iterations="$1"
  start_mysqld "$mysql_dir"
  "$mysql_dir"/install/bin/mysql -u root -e "DROP DATABASE IF EXISTS sysbench; CREATE DATABASE sysbench;"
  run_sysbench_test "$mysql_dir" oltp_read_write "$iterations" 10000 2500 "--range_selects=off --skip_trx"
  run_sysbench_test "$mysql_dir" oltp_update_index "$iterations" 10000 2500 "--range_selects=off --skip_trx"
  run_sysbench_test "$mysql_dir" oltp_delete "$iterations" 10000 2500 "--range_selects=off --skip_trx"
  run_sysbench_test "$mysql_dir" select_random_ranges "$iterations" 10000 2500 "--range_selects=off --skip_trx"
  run_sysbench_test "$mysql_dir" oltp_read_only "$iterations" 500000 30000 "--range_selects=off --skip_trx"
  stop_mysqld

  local -a benchmarks=( select_random_ranges oltp_delete oltp_read_only oltp_read_write oltp_update_index )
  for bn in "${benchmarks[@]}"; do
    rm -f "${mysql_dir}/sysbench.${bn}.result"
    for i in $(seq 1 "$iterations") ; do
      sed -nEe 's!^\s+transactions:\s+.*\((.*) per sec\.\)$!\1!p' ${mysql_dir}/sysbench_runfiles/"${bn}"."${i}".log >> "${mysql_dir}/sysbench.${bn}.result"
    done
  done
}

function sysbench_compare() {
  local -r base="$1"
  local -r test="$2"
  local -r iterations="$3"
  local -r ddir="$(dirname "$base")"
  local -a benchmarks=( select_random_ranges oltp_delete oltp_read_only oltp_read_write oltp_update_index )
  for bn in "${benchmarks[@]}"; do
    echo "$base .vs. $test: $bn"
    ${ddir}/t-test ${base}/sysbench.${bn}.result ${test}/sysbench.${bn}.result
  done
}

function run_perf() {
  /google/data/ro/projects/perf/perf record -a -e cycles:u -j any "$@"
}

"$@"
