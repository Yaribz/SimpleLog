# A Perl module implementing a basic logging functionality.
#
# Copyright (C) 2008-2020  Yann Riou <yaribzh@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

package SimpleLog;

use strict;

use FileHandle;
use File::Spec;

my $moduleVersion='0.9';


my $ansiCodesSupported=1;
if($^O eq 'MSWin32') {
  eval 'use Win32::Console::ANSI';
  $ansiCodesSupported=0 if($@);
}

my %defaultConf = (logFiles => [],
                   logLevels => [],
                   useANSICodes => [],
                   useTimestamps => [],
                   prefix => '');

my %defaultLog = (canonPath => undef,
                  level => 5,
                  useTimestamp => -t STDOUT ? 0 : 1,
                  useANSICode => -t STDOUT ? $ansiCodesSupported : 0);

my @levels = ('CRITICAL','ERROR   ','WARNING ','NOTICE  ','INFO    ','DEBUG   ');
my @ansiCodes = (35,31,33,32,37,36);

my %openHandles;

sub getVersion {
  return $moduleVersion;
}

sub _buildTimestamp {
  my @time = localtime();
  $time[4]++;
  @time = map(sprintf('%02d',$_),@time);
  return ($time[5]+1900).$time[4].$time[3].$time[2].$time[1].$time[0]
}

sub _registerFileHandle {
  my $filePath=shift;
  my $canonPath=File::Spec->canonpath($filePath);
  $canonPath=lc($canonPath) if($^O eq 'MSWin32');
  if(! exists $openHandles{$canonPath}) {
    my $fileHandle = new FileHandle;
    $fileHandle->open($filePath,'>>:encoding(utf-8)')
        or return undef;
    $fileHandle->autoflush(1);
    $openHandles{$canonPath}={fh => $fileHandle, count => 1};
  }else{
    $openHandles{$canonPath}{count}++;
  }
  return $canonPath;
}

sub new {
  my ($objectOrClass,%params) = @_;
  my $class = ref($objectOrClass) || $objectOrClass;
  my $self = {logs => [\%defaultLog]};
  bless ($self, $class);
  foreach my $param (keys %defaultConf) {
    $self->{$param}=$defaultConf{$param};
  }
  foreach my $param (keys %params) {
    if(grep($param,(keys %defaultConf))) {
      $self->{$param}=$params{$param};
    }else{
      $self->log("[SimpleLog] Ignoring invalid constructor parameter \"$param\"",2)
    }
  }
  my @logFiles = @{$self->{logFiles}};
  my @logLevels = @{$self->{logLevels}};
  my @useANSICodes = @{$self->{useANSICodes}};
  my @useTimestamps = @{$self->{useTimestamps}};
  if( ($#logFiles != $#logLevels) 
    || ($#logFiles != $#useANSICodes)
    || ($#logFiles != $#useTimestamps) ) {
    $self->log("[SimpleLog] Unable to initialize SimpleLog, inconsistent constructor parameters",0);
    return 0;
  }
  my @logs;
  my $logIndex=0;
  for my $paramIndex (0..$#logFiles) {
    my $logFile=$logFiles[$paramIndex];
    my $logLevel=$logLevels[$paramIndex];
    my $useANSICode=$useANSICodes[$paramIndex];
    my $useTimestamp=$useTimestamps[$paramIndex];
    my $logFileCanonPath;
    if($logFile) {
      $logFileCanonPath=_registerFileHandle($logFile);
      if(! defined $logFileCanonPath) {
        $self->log("[SimpleLog] Unable to open \"$logFile\" for writing",1);
        next;
      }
    }
    if(! grep {/^$logLevel$/} (0..5)) {
      $self->log("[SimpleLog] invalid log level \"$logLevel\"",1);
      next;
    }
    if($useANSICode != 0 && $useANSICode != 1) {
      $self->log("[SimpleLog] invalid useANSICode value \"$useANSICode\"",1);
      next;
    }
    if($useANSICode && ! $ansiCodesSupported) {
      $self->log("[SimpleLog] ignoring useANSICode mode (not supported by terminal)",2);
      $useANSICode=0;
    }
    if($useTimestamp != 0 && $useTimestamp != 1) {
      $self->log("[SimpleLog] invalid useTimestamp value \"$useTimestamp\"",1);
      next;
    }
    my %log = ( canonPath => $logFileCanonPath,
                level => $logLevel,
                useANSICode => $useANSICode,
                useTimestamp => $useTimestamp );
    $logs[$logIndex]=\%log;
    $logIndex++;
  }
  $self->{logs}=\@logs;
  return $self;
}

sub DESTROY {
  my $self=shift;
  foreach my $r_log (@{$self->{logs}}) {
    next unless(defined $r_log->{canonPath});
    if(--$openHandles{$r_log->{canonPath}}{count} == 0) {
      delete $openHandles{$r_log->{canonPath}};
    }
  }
}

sub log {
  my ($self,$m,$l) = @_;
  $m=$self->{prefix}.$m;
  my @logs=@{$self->{logs}};
  if($#logs == -1) {
    push(@logs,\%defaultLog);
    $self->{logs}=\@logs;
    $self->log("[SimpleLog] No log file configured, redirecting to standard output",1);
  }
  foreach my $p_log (@logs) {
    my %log=%{$p_log};
    return if($l > $log{level});
    my $ts = '';
    if($log{useTimestamp}) {
      $ts=_buildTimestamp()." - ";
    }
    my ($coloredAnsiSequence,$coloredBoldAnsiSequence,$normalAnsiSequence)=('','','');
    if($log{useANSICode}) {
      $coloredAnsiSequence="[0;$ansiCodes[$l]m";
      $coloredBoldAnsiSequence="[1;$ansiCodes[$l]m";
      $normalAnsiSequence="[0m";
    }
    my $logMessage=$coloredAnsiSequence.$ts.$coloredBoldAnsiSequence.$levels[$l].$coloredAnsiSequence." - $m$normalAnsiSequence\n";
    if(defined $log{canonPath}) {
      my $fh=$openHandles{$log{canonPath}}{fh};
      print $fh $logMessage;
    }else{
      print $logMessage;
    }
  }
}

sub setLevels {
  my ($self,$p_levels)=@_;
  my $nbLevels=$#{$p_levels};
  if($nbLevels > $#{$self->{logs}}) {
    $self->log("[SimpleLog] setLevels called with too many level values",2);
    $nbLevels=$#{$self->{logs}};
  }
  for my $i (0..$nbLevels) {
    my $newLevel=$p_levels->[$i];
    next unless(defined $newLevel);
    if($newLevel !~ /^\d+$/ || $newLevel > 5) {
      $self->log("[SimpleLog] ignoring invalid new log level in setLevels call ($newLevel)",2);
      next;
    }
    $self->{logs}->[$i]->{level}=$newLevel;
  }
}

1;
