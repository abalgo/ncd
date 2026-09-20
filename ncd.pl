#! /usr/bin/perl
use Cwd 'abs_path';
$ncdfile =  $ENV{'NCDfile'} || "$ENV{HOME}/.ncdpath";
if (-f $ncdfile ) {
   open(F,$ncdfile);
   @p=(<F>);
   close(F);
}
else {
   @p=();
   print stderr "$ncdfile file does not exist ... creating";
   open(F,">$ncdfile");
   close(F);
}

$directsave=0;
$latest="";
$niter=0;
@matches=();
$a=$ARGV[0];
$a=$ENV{"HOME"} if $a eq "";
open(F,"$ncdfile.mem") && do { $latest=<F>; $latest=~ s/[\r\n]+//g; $niter=<F>; $niter=~ s/[\r\n]+//g;  close(F);};
if ($a eq $latest) {
    $niter++;
}
else {
    $niter=0;
}

if ($ARGV[0] eq "-SWAPLAST") {
   $cwd=abs_path(".");
   $latest=" -@1";
   $niter=0;
   my @q=$cwd;
   @q = ($cwd,grep( ! /^${cwd}$/, @p[0..20]));
   $swapn=$ARGV[1] || 2;
   $np = $q[$swapn-1];
   $a=$np;
   update($np);
   exit;
}


if (-d $a) {
   $np=abs_path($a);
   $a=$np;
   $cwd=abs_path(".");
   update($np);
   exit;
}
else {
   @matchp=grep( m#/$a$#, @p);
   @matchq=grep( m#/$a/.*$#, @p);
   @matchr=grep( m#/$a[^/]+$#, @p);
   @matchs=grep( m#/$a.+/.*$#, @p);
   @matches=(@matchp,@matchq,@matchr,@matchs);
   if (@matches==0) {
       print stderr "No match!\nTrying case insensistive\n";
       @matchp=grep( m#/$a[^/]*$#i, @p);
       @matchq=grep( m#/$a.*/.*$#i, @p);
       @matches=(@matchp,@matchq,@matchr,@matchs);
    }
   if (@matches==0) {
       print stderr "No match!\nTrying inside path\n";
       @matchr=grep( m#[^/]$a[^/]*$#, @p);
       @matchs=grep( m#[^/]$a.*/.*$#, @p);
       @matches=(@matchp,@matchq,@matchr,@matchs);
       #shorting(@matches);
    }
   if (@matches==0) {
       print stderr "No match!\nTrying case inside path case insensitive\n";
       @matchr=grep( m#[^/]$a[^/]*$#i, @p);
       @matchs=grep( m#[^/]$a.*/.*$#i, @p);
       @matches=(@matchp,@matchq,@matchr,@matchs);
       #shorting(@matches);
    }

   if (@matches==0) {
      print stderr "No match!\nTrying cd instead...\n";
      print $a;
   }
   else {
      shorting(@matches);
      $niter=$niter % @matches;
      $cwd=abs_path(".");
      if (@matches>1) {
         $niter=($niter+1) % @matches if $cwd eq $matches[$niter];
      }
      print stderr "@matches\n" if @ARGV>1;
      update($matches[$niter]);
   }
}

sub update($) {
   my ($np)=@_;
   if (/.*$a/) {
      $np =~ s/(.*$a.*?)\/.*/$1/;
   }
   else {
      $np =~ s/(.*$a.*?)\/.*/$1/i;
   }
   $np=~s/\n//g;
   if ($latest ne $a) {
       open(F,">$ncdfile");
       print F "$np\n" if $directsave;
       print F "$cwd\n";
       if ($directsave) {
           @x=grep not(/^${np}$/ || /^${cwd}$/) , @p;
       }
       else {
           @x=grep not(/^${cwd}$/) , @p;
       }
       print F join("", @x);
       close(F);
    }

   open(F,">$ncdfile.mem");
   print F "$a\n";
   print F "$niter\n";
   close(F);
   #$np=~ s/(['" ])/\\$1/g;
   print stderr "\n   --> cd $np\n";
   print "$np";
}


sub shorting {
  @rtn=();
  my $x;
  map {s/[\r\n]*//g;} @matches;
  while(@matches) {
     $x = $matches[0];
	 $x =~ s/^(.*$a[^\/]*).*$/$1/i;
     push @rtn, $x;
	 @matches=grep (!/^$x(\/|$)/, @matches[1..$#matches]); # if $x =~ /$a(\/|$)/;
  }
  @matches=@rtn;
  map {s/$/\n/;} @matches;
}
