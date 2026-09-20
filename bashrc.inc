function ncd() {
   export PPATH=$PWD
   export ncdt=`$HOME/bin/ncd.pl $*`;
   cd "$ncdt"
   export NCDLastSearch=$1
}

function ncs() {
   export NCDLastSearch="";
   export PPATH=$PWD
   export ncdt=`$HOME/bin/ncd.pl -SWAPLAST $*`;
   cd "$ncdt"
}
