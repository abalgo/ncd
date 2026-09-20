#! /usr/bin/perl
#
# Test suite for ncd.pl.   Run with:  prove -v t/ncd.t     or   perl t/ncd.t
#
# Each test builds a throw-away directory tree and a throw-away history file,
# then drives ncd.pl exactly like bashrc.inc does (capture stdout, chdir to it).

use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Basename qw(dirname);
use File::Spec;
use Cwd qw(getcwd abs_path);

my $SCRIPT = File::Spec->rel2abs(dirname(__FILE__) . '/../ncd.pl');
plan skip_all => "ncd.pl not found at $SCRIPT" unless -f $SCRIPT;

my $ROOT = tempdir(CLEANUP => 1);
$ROOT = abs_path($ROOT);
my $HIST = "$ROOT/.ncdpath";
my $HOME = "$ROOT/home";

$ENV{NCDfile}  = $HIST;
$ENV{NCDquiet} = 1;
$ENV{HOME}     = $HOME;

# ------------------------------------------------------------------ helpers

sub mkdirs { make_path("$ROOT/$_") for @_; }

# Seed the history file, most recent first.
sub seed {
    open(my $fh, '>', $HIST) or die $!;
    print $fh "$ROOT/$_\n" for @_;
    close($fh);
    unlink "$HIST.mem";
}

sub history {
    open(my $fh, '<', $HIST) or return ();
    my @l = <$fh>;
    close($fh);
    chomp @l;
    return map { my $x = $_; $x =~ s/^\Q$ROOT\E\/?//; $x } @l;
}

# Run ncd.pl from $cwd (relative to $ROOT) and return its stdout, relative to
# $ROOT when it points inside the sandbox.
sub ncd {
    my ($cwd, @args) = @_;
    my $old = getcwd();
    chdir("$ROOT/$cwd") or die "chdir $ROOT/$cwd: $!";
    open(my $fh, '-|', $^X, $SCRIPT, @args) or die "run: $!";
    my $out = do { local $/; <$fh> };
    close($fh);
    chdir($old);
    $out = '' unless defined $out;
    $out =~ s/^\Q$ROOT\E\/?//;
    return $out;
}

# ------------------------------------------------------------------- set-up

mkdirs(
    'home',
    'work/projects/ncd',
    'work/projects/ncdtest',
    'work/projects/ncd/src',
    'work/archive/ncd',
    'work/NCD_upper',
    'work/my-ncd-stuff',
    'work/a+b',
    'work/x.y',
    'work/with space',
    'work/alpha/beta',
);

# ------------------------------------------------------- exact basename wins

seed('work/projects/ncdtest', 'work/projects/ncd/src', 'work/archive/ncd');
is(ncd('home', 'ncd'), 'work/projects/ncd',
    'exact basename beats a prefix match, and the path is cut at the match');

# ---------------------------------------- truncation uses the right component

seed('work/projects/ncdtest/');
is(ncd('home', 'ncdtest'), 'work/projects/ncdtest',
    'trailing slash in the history is tolerated');

seed('work/projects/ncd/src');
is(ncd('home', 'ncd'), 'work/projects/ncd',
    'a deep entry is cut back to the named component, not the deepest one');

# --------------------------------------------------------------- the rotation

seed('work/projects/ncd', 'work/archive/ncd', 'work/projects/ncdtest');
my @seen;
push @seen, ncd('home',   'ncd');
push @seen, ncd($seen[0], 'ncd');
push @seen, ncd($seen[1], 'ncd');
is_deeply(
    \@seen,
    [ 'work/projects/ncd', 'work/archive/ncd', 'work/projects/ncdtest' ],
    'repeating the query walks the whole match list in order'
);
is(ncd($seen[2], 'ncd'), 'work/projects/ncd', 'the rotation wraps around');

seed('work/projects/ncd', 'work/archive/ncd', 'work/projects/ncdtest');
is(ncd('home', 'ncd'),  'work/projects/ncd', 'rotation: first hit');
is(ncd('home', 'ncdt'), 'work/projects/ncdtest',
    'a different query resets the rotation');
is(ncd('home', 'ncd'), 'work/projects/ncd',
    'and coming back to the first query restarts from the top');

# ------------------------------------------------- never return the cwd (bug)

seed('work/projects/ncd', 'work/archive/ncd');
is(ncd('work/projects/ncd', 'ncd'), 'work/archive/ncd',
    'a match equal to the current directory is skipped');

seed('work/projects/ncd');
is(ncd('work/projects/ncd', 'ncd'), 'work/projects/ncd',
    'unless it is the only match');

# ------------------------------------------------- real directories win (bug)

seed('work/archive/ncd');
is(ncd('work/projects', '.'), 'work/projects', 'ncd . stays where it is');
is(ncd('work/projects', '..'), 'work', 'ncd .. goes exactly one level up');
is(ncd('work', 'projects'), 'work/projects', 'an existing subdir is used as-is');

# ----------------------------------------------------- regex metacharacters

seed('work/a+b', 'work/x.y');
is(ncd('home', 'a+b'), 'work/a+b', 'a "+" in the name is matched literally');
is(ncd('home', 'x.y'), 'work/x.y', 'a "." in the name is matched literally');

seed('work/alpha/beta');
is(ncd('home', 'xqy'), 'xqy', 'no match: the query is echoed back for plain cd');

# ------------------------------------------------------------ case and substring

seed('work/NCD_upper');
is(ncd('home', 'ncd_up'), 'work/NCD_upper', 'case-insensitive prefix fallback');

# ------------------------------------------------------------- smart case

seed('work/projects/ncd', 'work/NCD_upper');
is(ncd('home', 'ncd'), 'work/projects/ncd',
    'an all-lower-case query ignores case: the exact component wins');

seed('work/projects/ncd', 'work/NCD_upper');
is(ncd('home', 'NCD'), 'work/NCD_upper',
    'an upper-case letter forces case-sensitivity: lower-case ncd is not a match');

seed('work/projects/ncd');
is(ncd('home', 'NCD'), 'NCD',
    'a case-sensitive query with no match falls back to a plain cd');

seed('work/NCD_upper');
is(ncd('home', 'NCD_upper'), 'work/NCD_upper', 'exact case-sensitive match');

seed('work/NCD_upper');
is(ncd('home', 'Upper'), 'Upper',
    'case-sensitivity really bites: Upper does not match NCD_upper');

seed('work/NCD_upper');
is(ncd('home', 'upper'), 'work/NCD_upper',
    'the same fragment in lower case does match it');

seed('work/my-ncd-stuff');
is(ncd('home', 'ncd'), 'work/my-ncd-stuff', 'substring fallback inside a name');

seed('work/my-ncd-stuff', 'work/projects/ncd');
is(ncd('home', 'ncd'), 'work/projects/ncd',
    'an exact component still beats a substring found more recently');

# ------------------------------------------------------- multi-segment query

seed('work/projects/ncd/src', 'work/archive/ncd');
is(ncd('home', 'projects/ncd'), 'work/projects/ncd',
    'a query with a slash matches consecutive components');

# ------------------------------------------------------------ spaces in paths

seed('work/with space');
is(ncd('home', 'with space'), 'work/with space', 'paths with spaces work');

# ----------------------------------------------------------- history updates

seed('work/archive/ncd', 'work/alpha');
ncd('home', 'ncd');
my @h = history();
is($h[0], 'work/archive/ncd', 'the destination is recorded first');
is($h[1], 'home',             'the directory we left is recorded second');
is(scalar(grep { $_ eq 'work/archive/ncd' } @h), 1, 'no duplicate entry');

# --------------------------------------------------- vanished directories

make_path("$ROOT/work/gone");
seed('work/gone', 'work/alpha/beta');
rmdir "$ROOT/work/gone";
is(ncd('home', 'gone'), 'gone',
    'a vanished directory is never returned as a match');

make_path("$ROOT/work/gone");
seed('work/gone', 'work/alpha');
rmdir "$ROOT/work/gone";
ncd('home', 'alpha');
ok(grep({ $_ eq 'work/gone' } history()),
    'by default a vanished directory stays in the history file');

make_path("$ROOT/work/gone");
seed('work/gone', 'work/alpha');
rmdir "$ROOT/work/gone";
{
    local $ENV{NCDautoremove} = 1;
    ncd('home', 'alpha');
}
ok(!grep({ $_ eq 'work/gone' } history()),
    'NCDautoremove=1 prunes it from the history file');

# skipping a vanished entry must not disturb the rotation
make_path("$ROOT/work/ncd_gone");
seed('work/projects/ncd', 'work/ncd_gone', 'work/archive/ncd');
rmdir "$ROOT/work/ncd_gone";
is(ncd('home', 'ncd'), 'work/projects/ncd', 'rotation with a stale entry: 1st');
is(ncd('home', 'ncd'), 'work/archive/ncd',
    'the stale entry is skipped, the rotation goes straight to the next one');

# the rotation must never spin: one full cycle then stop
mkdirs('work/d1/ncd', 'work/d2/ncd', 'work/d3/ncd');
seed('work/d1/ncd', 'work/d2/ncd', 'work/d3/ncd');
is(ncd('home', 'ncd'), 'work/d1/ncd', 'rotation primed over three matches');
rmdir "$ROOT/work/d2/ncd";
rmdir "$ROOT/work/d3/ncd";
is(ncd('work/d1/ncd', 'ncd'), 'work/d1/ncd',
    'every other cached match died: one cycle, then fall back to the cwd');
mkdirs('work/d2/ncd', 'work/d3/ncd');

# the cached list dies entirely -> fresh search instead of a bogus "no match"
mkdirs('work/tmp1/zzz');
seed('work/tmp1/zzz', 'work/projects/ncd');
is(ncd('home', 'zzz'), 'work/tmp1/zzz', 'prime the cache on a single match');
rmdir "$ROOT/work/tmp1/zzz";
mkdirs('work/tmp2/zzz');
seed('work/tmp2/zzz');    # history rebuilt, but .mem still holds the dead one
open(my $memfh, '>', "$HIST.mem") or die $!;
print $memfh "zzz\n0\n$ROOT/work/tmp1/zzz\n";
close($memfh);
is(ncd('home', 'zzz'), 'work/tmp2/zzz',
    'a fully stale cache triggers a fresh search, not a "no match"');

# all matches dead -> give up cleanly, no loop
mkdirs('work/dead/qqq');
seed('work/dead/qqq');
rmdir "$ROOT/work/dead/qqq";
is(ncd('home', 'qqq'), 'qqq', 'when every match is dead, fall back to a plain cd');

# ------------------------------------------------------------------- NCDmax

seed('work/alpha', 'work/archive', 'work/projects');
{
    local $ENV{NCDmax} = 2;
    ncd('home', 'alpha');
}
cmp_ok(scalar(history()), '<=', 2, 'NCDmax caps the history when it is set');

seed('work/alpha', 'work/archive', 'work/projects', 'work/x.y', 'work/a+b');
ncd('home', 'alpha');
cmp_ok(scalar(history()), '>=', 6, 'the history is unlimited by default');

# ------------------------------------------------------------------ SWAPLAST

seed('work/alpha', 'work/archive', 'work/projects');
is(ncd('home', '-SWAPLAST'), 'work/alpha', 'ncs goes to the last directory');
is(ncd('work/alpha', '-SWAPLAST'), 'home', 'ncs toggles back');
is(ncd('home', '-SWAPLAST'), 'work/alpha', 'and forth');

seed('work/alpha', 'work/archive', 'work/projects');
is(ncd('home', '-SWAPLAST', '3'), 'work/archive', 'ncs 3 reaches the third slot');

seed('work/alpha');
is(ncd('home', '-SWAPLAST', '9'), 'work/alpha',
    'an n larger than the history is clamped');

# a swap must not be mistaken for a repeated search
seed('work/projects/ncd', 'work/archive/ncd');
is(ncd('home', 'ncd'), 'work/projects/ncd', 'search before swap');
ncd('work/projects/ncd', '-SWAPLAST');
is(ncd('home', 'ncd'), 'work/projects/ncd',
    'a swap in between resets the rotation instead of advancing it');

# --------------------------------------------------------------- no argument

seed('work/alpha');
is(ncd('work', ), 'home', 'no argument goes home');

# ------------------------------------------------------------- empty history

unlink $HIST, "$HIST.mem";
is(ncd('home', 'ncd'), 'ncd', 'an empty history falls back to a plain cd');
ok(-f $HIST, 'the history file is created on the fly');

done_testing();
