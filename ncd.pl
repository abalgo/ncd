#! /usr/bin/perl
#
# ncd.pl -- resolve a directory from the navigation history.
#
# Reads a MRU history file (one absolute path per line, most recent first),
# picks the best match for the fragment given on the command line, prints the
# resulting path on stdout and updates the history.  The calling shell function
# (see bashrc.inc) is responsible for the actual `cd`.
#
# Repeating the exact same query rotates through the remaining matches: the
# candidate list is cached in the .mem file so the rotation stays stable even
# though the history is rewritten on every call.
#
# Environment:
#   NCDfile      history file            (default: $HOME/.ncdpath)
#   NCDmax       history size            (default: unlimited)
#   NCDautoremove  if set, drop vanished directories from the history file
#                  (off by default: they are only reported and skipped)
#   NCDquiet     if set, suppress the informational messages on stderr
#
# Usage:
#   ncd.pl [-v] [-l] <fragment>
#   ncd.pl -SWAPLAST [n]
#
# Smart case: an all-lower-case fragment matches regardless of case; a fragment
# containing an upper-case letter is matched case-sensitively.

use strict;
use warnings;
use Cwd qw(abs_path getcwd);

my $HISTFILE = $ENV{NCDfile} || (($ENV{HOME} || '.') . '/.ncdpath');
my $MEMFILE  = "$HISTFILE.mem";
my $MAXHIST  = (defined $ENV{NCDmax} && $ENV{NCDmax} =~ /^\d+$/)
             ? $ENV{NCDmax} : 0;          # 0 = unlimited
my $AUTORM   = $ENV{NCDautoremove} ? 1 : 0;
my $QUIET    = $ENV{NCDquiet}      ? 1 : 0;
my $VERBOSE  = 0;
my $CASESENS = 0;    # smart case: set when the query holds an upper-case letter

my @hist;    # current history, most recent first (no trailing newlines)

# ---------------------------------------------------------------- utilities

sub info { print STDERR @_ unless $QUIET; }

# Canonical form: no newline, no trailing slash (except for "/").
sub norm {
    my ($p) = @_;
    return '' unless defined $p;
    $p =~ s/[\r\n]+//g;
    $p =~ s{/+$}{} unless $p =~ m{^/+$};
    return $p;
}

# Keep only the directories that still exist; report the others and move on.
# They stay in the history file unless NCDautoremove is set.
sub existing {
    my @out;
    for my $d (@_) {
        if (-d $d) { push @out, $d }
        else       { info "ncd: $d no longer exists, skipping\n" }
    }
    return @out;
}

sub uniq {
    my %seen;
    return grep { length($_) && !$seen{$_}++ } @_;
}

sub usage {
    print STDERR "usage: ncd.pl [-v] <fragment>   jump to the best match in the history\n";
    print STDERR "       ncd.pl <fragment>        repeat to rotate through the other matches\n";
    print STDERR "       ncd.pl -SWAPLAST [n]     rotate among the n last directories (n=2)\n";
    print STDERR "       ncd.pl -l                list the history\n";
    exit 0;
}

# ----------------------------------------------------------------- history

sub read_history {
    unless (-f $HISTFILE) {
        info "$HISTFILE does not exist ... creating\n";
        open(my $fh, '>', $HISTFILE) or die "ncd: cannot create $HISTFILE: $!\n";
        close($fh);
        return ();
    }
    open(my $fh, '<', $HISTFILE) or die "ncd: cannot read $HISTFILE: $!\n";
    my @p = map { norm($_) } <$fh>;
    close($fh);
    return uniq(@p);
}

# Push $target then $cwd on top of the history and drop duplicates.  Both the
# directory we leave and the one we enter are recorded -- the old version only
# ever recorded the former.  Vanished entries are kept unless NCDautoremove is
# set: a directory may be temporarily gone (unmounted share, detached volume).
sub write_history {
    my ($target, $cwd) = @_;
    my @new = uniq($target, $cwd, @hist);
    @new = grep { -d $_ } @new if $AUTORM;
    @new = @new[0 .. $MAXHIST - 1] if $MAXHIST && @new > $MAXHIST;
    open(my $fh, '>', $HISTFILE) or die "ncd: cannot write $HISTFILE: $!\n";
    print $fh map { "$_\n" } @new;
    close($fh);
}

# --------------------------------------------------------------- mem file
# Line 1: last query, line 2: last index, following lines: cached candidates.

sub read_mem {
    return ('', 0) unless -f $MEMFILE;
    open(my $fh, '<', $MEMFILE) or return ('', 0);
    my @l = map { norm($_) } <$fh>;
    close($fh);
    my $query = @l ? shift(@l) : '';
    my $idx   = @l ? shift(@l) : 0;
    $idx = 0 unless defined $idx && $idx =~ /^\d+$/;
    return ($query, $idx, @l);
}

sub write_mem {
    my ($query, $idx, $cands) = @_;
    open(my $fh, '>', $MEMFILE) or return;
    print $fh (defined $query ? $query : ''), "\n";
    print $fh (defined $idx   ? $idx   : 0), "\n";
    print $fh map { "$_\n" } @{ $cands || [] };
    close($fh);
}

# --------------------------------------------------------------- matching

# Rank a path component against the query.  Lower is better, 0 means no match.
# Smart case: a query holding an upper-case letter is taken as deliberate and
# matched case-sensitively; an all-lower-case query ignores case entirely.
sub tier {
    my ($comp, $q) = @_;
    if ($CASESENS) {
        return 1 if $comp eq $q;
        return 2 if $comp =~ /^\Q$q\E/;
        return 3 if index($comp, $q) >= 0;
        return 0;
    }
    return 1 if lc($comp) eq lc($q);
    return 2 if $comp =~ /^\Q$q\E/i;
    return 3 if $comp =~ /\Q$q\E/i;
    return 0;
}

# Every history path is cut just after the component that matched, so the
# result is the directory the user named -- not the deeper one that happened
# to be in the history.  A query containing slashes matches a run of
# consecutive components.
sub candidates {
    my ($q) = @_;
    my @qs = grep { length } split m{/}, $q;
    return () unless @qs;
    my $k    = scalar @qs;
    my $want = join('/', @qs);

    my %best;    # path => [tier, history position]
    my $pos = 0;
    for my $path (@hist) {
        my @c = split m{/}, $path, -1;
        for my $i ($k - 1 .. $#c) {
            my @win = @c[ $i - $k + 1 .. $i ];
            next if grep { !length } @win;
            my $t = tier(join('/', @win), $want);
            next unless $t;
            my $cand = join('/', @c[ 0 .. $i ]);
            $cand = '/' unless length $cand;
            if (  !exists $best{$cand}
                || $t < $best{$cand}[0]
                || ($t == $best{$cand}[0] && $pos < $best{$cand}[1]))
            {
                $best{$cand} = [ $t, $pos ];
            }
        }
        $pos++;
    }

    my @out = sort {
               $best{$a}[0] <=> $best{$b}[0]     # best tier first
            || $best{$a}[1] <=> $best{$b}[1]     # then most recently used
            || length($a)   <=> length($b)       # then shortest
            || $a cmp $b
    } keys %best;

    return @out;
}

# Starting at $idx, walk @cand and return the index of the first entry that is
# usable: it must still exist on disk, and must not be the directory we are
# already in.  The walk covers *exactly one* cycle and never more, so a list
# full of vanished entries terminates instead of spinning forever.  The cwd is
# returned as a last resort when nothing else survives, and -1 when nothing at
# all does.
sub pick {
    my ($idx, $cwd, @cand) = @_;
    my $n = scalar @cand;
    return -1 unless $n;
    my $fallback = -1;
    my %reported;
    for (1 .. $n) {
        my $p = $cand[$idx];
        if (!-d $p) {
            info "ncd: $p no longer exists, skipping\n" unless $reported{$p}++;
        }
        elsif ($p ne $cwd) { return $idx }
        elsif ($fallback < 0) { $fallback = $idx }
        $idx = ($idx + 1) % $n;
    }
    return $fallback;
}

# ------------------------------------------------------------------ output

sub finish {
    my ($target, $cwd, $query, $idx, $cands) = @_;
    $target = norm($target);
    write_history($target, $cwd);
    write_mem($query, $idx, $cands);
    if ($VERBOSE && $cands && @$cands) {
        info "candidates:\n";
        info(($_ eq $target ? ' -> ' : '    '), $_, "\n") for @$cands;
    }
    info "\n   --> cd $target\n";
    print $target;
    exit 0;
}

# -------------------------------------------------------------------- main

my ($swaplast, $swapn, $list, $query);
my @argv = @ARGV;
while (@argv) {
    my $x = shift @argv;
    if ($x eq '-SWAPLAST') {
        $swaplast = 1;
        $swapn = (@argv && $argv[0] =~ /^\d+$/) ? shift(@argv) : 2;
    }
    elsif ($x eq '-v' || $x eq '--verbose') { $VERBOSE = 1 }
    elsif ($x eq '-l' || $x eq '--list')    { $list    = 1 }
    elsif ($x eq '-h' || $x eq '--help')    { usage() }
    elsif (!defined $query)                 { $query   = $x }
    else                                    { $VERBOSE = 1 }    # legacy
}

my $cwd = norm(getcwd());
@hist = read_history();

if ($list) {
    info map { "$_\n" } @hist;
    print $cwd;
    exit 0;
}

if ($swaplast) {
    # Ring over the last directories; $cwd is index 1, so the default n=2 is
    # the equivalent of `cd -`.
    my @ring = ($cwd, grep { $_ ne $cwd } @hist);
    @ring = existing(@ring);
    my $idx = $swapn - 1;
    $idx = $#ring if $idx > $#ring;
    $idx = 0      if $idx < 0;
    # A swap is not a search: forget any pending rotation.
    finish($ring[$idx], $cwd, '', 0, []);
}

$query = $ENV{HOME} unless defined $query && length $query;

# Smart case, decided once for the whole run.
$CASESENS = ($query =~ /[[:upper:]]/) ? 1 : 0;

# An existing directory always wins over a history lookup.
if (-d $query) {
    finish(norm(abs_path($query)), $cwd, '', 0, []);
}

my ($lastq, $lastidx, @cached) = read_mem();
my (@cand, $idx);
my $rotating = (length($lastq) && $lastq eq $query && @cached) ? 1 : 0;

if ($rotating) {
    # Same query repeated: rotate over the cached list rather than recomputing
    # it, so that rewriting the history in between cannot shuffle the order.
    # The list is kept as-is, vanished entries included, so that $lastidx keeps
    # pointing at the same candidates as on the previous call.
    @cand = @cached;
    $idx  = ($lastidx + 1) % scalar(@cand);
}
else {
    @cand = candidates($query);
    $idx  = 0;
}

$idx = pick($idx, $cwd, @cand);

# The whole cached list went stale: fall back to a fresh search rather than
# claiming there is no match.
if ($idx < 0 && $rotating) {
    @cand = candidates($query);
    $idx  = pick(0, $cwd, @cand);
}

if ($idx < 0) {
    info "ncd: no match for '$query', trying cd instead\n";
    write_mem('', 0, []);
    print $query;
    exit 1;
}

finish($cand[$idx], $cwd, $query, $idx, \@cand);
