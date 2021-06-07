#!/usr/bin/env bash

case "$(uname -s)" in
MINGW*|CYGWIN*) 
SILICE_DIR=`cygpath $SILICE_DIR`
BUILD_DIR=`cygpath $BUILD_DIR`
FRAMEWORKS_DIR=`cygpath $FRAMEWORKS_DIR`
FRAMEWORK_FILE=`cygpath $FRAMEWORK_FILE`
BOARD_DIR=`cygpath $BOARD_DIR`
;;
*)
esac

echo "build script: SILICE_DIR     = $SILICE_DIR"
echo "build script: BUILD_DIR      = $BUILD_DIR"
echo "build script: BOARD_DIR      = $BOARD_DIR"
echo "build script: FRAMEWORKS_DIR = $FRAMEWORKS_DIR"
echo "build script: FRAMEWORK_FILE = $FRAMEWORK_FILE"

export PATH=$PATH:$SILICE_DIR:$SILICE_DIR/../tools/fpga-binutils/mingw64/bin/
case "$(uname -s)" in
MINGW*)
export PYTHONHOME=/mingw64/bin
export PYTHONPATH=/mingw64/lib/python3.8/
export QT_QPA_PLATFORM_PLUGIN_PATH=/mingw64/share/qt5/plugins
;;
*)
esac

cd $BUILD_DIR

rm build*
rm -r formal* *.smtc  # formal.log formal.sby *.smtc formal_*/

silice --frameworks_dir $FRAMEWORKS_DIR -f $FRAMEWORK_FILE -o build.v $1 "${@:2}"


if ! [[ -f build.v.alg.log ]]; then
    >&2 echo "File '$PWD/build.v.alg.log' not found. Did the compiler generate one?"
    exit 1
fi

LOG_LINES="$(cat build.v.alg.log)"
LOG_LINES="$(sed -e '/./,$!d' -e :a -e '/^\n*$/{$d;N;ba' -e '}' <<< "$LOG_LINES")"
# adaptated from: https://unix.stackexchange.com/a/552195
# Remove empty lines at the beginning and end of the string
SMTC='initial
assume (= [reset] true)

state 1:*
assume (= [reset] false)

state 2:*
assume (= [in_run] true)

final
assume (= [in_run] false)'

touch formal.sby

I=0
echo "[tasks]" > formal.sby
while IFS= read -r LOG; do
    awk '$2 ~ /^formal(.*?)\$$/ { print $4 " task" $1 }' <<< "$I $LOG" >> formal.sby
    I=$((I + 1))
done <<< "$LOG_LINES"

I=0
echo "
[options]
mode bmc
depth 50
timeout 120
wait on" >> formal.sby
while IFS= read -r LOG; do
    awk -v SMTC="$SMTC" '
$2 ~ /^formal(.*?)\$$/ {
   SMTC_NAME=$4 ".smtc"

   print "task" $1 ": smtc " $4 ".smtc"
   print SMTC >SMTC_NAME
}' <<< "$I $LOG" >> formal.sby
    I=$((I + 1))
done <<< "$LOG_LINES"

echo "
[engines]
smtbmc --stbv --syn z3" >> formal.sby

I=0
echo "
[script]
read_verilog -formal build.v
" >> formal.sby
while IFS= read -r LOG; do
    awk '$2 ~ /^formal(.*?)\$$/ { print "task" $1 ": prep -top M_" $4 "_" $2 }' <<< "$I $LOG" >> formal.sby
    I=$((I + 1))
done <<< "$LOG_LINES"

echo "
[files]
build.v" >> formal.sby
for FILE in $(find . -maxdepth 1 -type f -name '*.smtc' -print | cut -c3-); do
    echo "$FILE" >> formal.sby
done

MAX_LENGTH=$(awk '{ n = length($1); if (n > len) len = n } END { print len + 3 }' <<< "$LOG_LINES")

if ! command -v sby &>/dev/null; then
    >&2 echo "##### Symbiyosys (sby) not found! #####"
    >&2 echo ""
    >&2 echo "Make sure it is installed and in your \$PATH."
    >&2 echo "For more information about installing, see <https://symbiyosys.readthedocs.io/en/latest/install.html>."
    exit 1
fi

echo "---< Running Symbiyosys >---"

AWKSCRIPT='
match($0, /Status: (failed|passed|PREUNSAT)/, gr) {
  split($3, n, /formal_/)
  gsub("PREUNSAT", "failed", gr[1])
  print "* " sprintf("%" LEN "-s", n[1] n[2]) gr[1]
};
{ printf "" }
'

sby -f formal.sby | tee logfile.txt | awk -v LEN=$MAX_LENGTH "$AWKSCRIPT"
# Because we're piping, we need to check if the status of the pipe is not ok.
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    echo ""
    echo "---< Results >---"
    AWKSCRIPT='
match($0, /(Assert failed in ).*?: build\.v:(.*)$/, gr) {
  build_v = "build.v"

  split($3, n, /formal_/)
  gsub(/[0-9]+\.[0-9]+-/, "", gr[2])
  gsub(/\.[0-9]+/, "", gr[2])

  line = gr[2]
  NR_ = 0
  gr[2] = "<original file not found>"
  while ((getline build_v_line < build_v) > 0) {
    if (++NR_ == line && match(build_v_line, /\/\/%(.*)$/, gr_)) {
      gr[2] = gr_[1]
      break
    }
  }
  close(build_v)

  print "* " sprintf("%" LEN "-s", n[1] n[2]) gr[1] gr[2]
}
match($0, /(Assumptions are unsatisfiable!)$/, gr) {
  split($3, n, /formal_/)

  print "* " sprintf("%" LEN "-s", n[1] n[2]) gr[1]
}
    '
    awk -v LEN=$MAX_LENGTH "$AWKSCRIPT" < logfile.txt
    exit 1
fi
