#!/usr/bin/perl -w
#
# Copyright: Sean Timmins 2013
# 
#
# Copyright (c) 2013-2015, Sean Timmins (stimmins@wiley.com)
# Copyright (c) 2017 Jonathan Tietz
#
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
#
#
require 5.004;
use strict;

use Getopt::Std;

# Function prototypes
sub output($$$);
sub parse_file($);
sub get_file_list($);
sub VERSION_MESSAGE();

# Globals
use vars qw (@filelist $configfile @directives $serverroot $nest_level $verbose $quiet 
             $print_filename $print_line_no @defaultconf);

# Some defaults for globals
$verbose = 0;
$quiet = 0;
$print_filename=1;
$print_line_no=1;
$serverroot="";

# Some default files to try for the top level configuration file
# Taken from: http://wiki.apache.org/httpd/DistrosDefaultLayout
@defaultconf = ("/usr/local/apache2/conf/httpd.conf", # apache httpd default
                "/etc/apache2/apache2.conf",          # Debian, Ubunt
                "/etc/httpd/conf/httpd.conf",         # Fedora Core, CentOS, RHEL, Mandriva
                "/etc/apache2/httpd.conf",            # Mac OS X, Solaris 10, openSUSE, SLES, Gentoo
                "/usr/pkg/etc/httpd/httpd.conf",      # NetBSD
                "/usr/local/etc/apache22/httpd.conf", # FreeBSD 6.1 (Apache httpd 2.2)
                "/usr/local/etc/apache2/httpd.conf",  # FreeBSD 6.1 (Apache httpd 2.0)
                "/var/www/conf/httpd.conf",           # OpenBSD 5.0 (Apache httpd 1.3)
                "/etc/apache2/httpd2.conf",           # OpenBSD 5.0 (Apache httpd 2.2)
                "C:/Program Files/Apache Software Foundation/Apache2.2/conf/httpd.conf",   # Win32 (Apache httpd 2.2):
                "/etc/httpd/httpd.conf"               # Slackware 14.0
               );

# Parse command line
my %opts;
getopts('c:FhLqvs:' , \%opts);

if ($opts{h})
{
  &VERSION_MESSAGE();
  exit(0);
}

# Set options based on arguments
$verbose=1 if ($opts{v});
$quiet=1 if ($opts{q});
$print_filename=0 if ($opts{F});
$print_line_no=0 if ($opts{L});

# Try to determine ServerRoot from the specified configuration file
$configfile=$opts{c};
if (!$configfile)
{
  print "Warning   : No configuration file specified.\n" unless ($quiet);
  print "Warning   : Searching common default locations\n" unless ($quiet);
  foreach my $file (@defaultconf)
  {
    if ( -f $file)
    {
      printf "Found     : Configuration file: $file\n" unless ($quiet);
      $configfile = $file;
    }
  }

  if (!$configfile)
  {
    print "Error: Unable to find a configuration file\n";
    print "Error: You must specify a configuration file to parse\n";
    print "Usage: $0 -c <configuration file>\n";
    exit(1);
  }
}
$serverroot=`grep -i ServerRoot $configfile | grep -E -v '^\\s*#' | awk '{print \$2}'`;
$serverroot=~ s/['"]//g;
chomp($serverroot);

# Try to determine ServerRoot from command line
$serverroot=$opts{s} if ($opts{s});

# If no valid ServerRoot then exit
if (!$serverroot)
{
  print "Error: Unable to determine server root from top level configuration file\n";
  print "Error: Please specify with -s flag\n";
  exit(1);
}

@directives=@ARGV;

print "ServerRoot: $serverroot\n" unless ($quiet);

# Just so we can print spaces to indent stuff
$nest_level=0;

# Parse the top level confoguration file
parse_file($configfile);

# Reads a file looking for directives and Include files
sub parse_file($)
{
  my $file = shift;
  my $line="";
  my @data =();
  my $DATA;
  my $line_no=0;
  my @glob_file_list=();
  my $file_in_list="";

  print "Starting  : $file\n" unless ($quiet);
  open($DATA,"<$file") || print "Unable to open: $file\n";

  push(@filelist,$file);
  while ($line = <$DATA>)
  {
    chomp($line);
    $line_no++;
  
    # Skip if the line stats with a hash
    next if ($line =~ /^#/);
  
    # First remove any comment and any leading spaces
    $line =~ s/#.*//;
    $line =~s/^\s+//;
    next if (!$line);

    # split the line into directive + the rest (the rest doesn't always exist)
    @data = split(/\s+/,$line,2);

    if ($data[0] =~ /^\<\//)
    {
      $nest_level--;
      output($data[0],$line_no, $data[1]);
    }
    elsif ($data[0] =~ /^\</)
    {
      output($data[0],$line_no, $data[1]);
      $nest_level++;
    }
    else
    {
      output($data[0],$line_no, $data[1]);
    }

    # If we found an Include or IncludeOptional directive we immediately parse the files
    #if ($data[0] =~ /^Include$/i)
    if ($data[0] =~ /^(Include|IncludeOptional)$/i)
    {
      printf "Include   : at line $line_no" unless ($quiet);
      if ($print_filename)
      {
        printf " ($filelist[$#filelist])" unless ($quiet);
      }
      print "\n" unless ($quiet);

      @glob_file_list = get_file_list($data[1]);
      foreach $file_in_list (@glob_file_list)
      {
        parse_file($file_in_list);
        pop(@filelist);
      }
      printf "Return to : $file\n" unless ($quiet);
    }
  }

  print "Ending    : $file\n" unless ($quiet);
}

# Takes the argument to an Include directive and returns a list of files it includes
sub get_file_list($)
{
  my $file = shift;
  my @file_list;

  if ($file !~ m{^/} && @filelist)
  {
    $file = $serverroot . '/' . $file;
  }

  @file_list = glob($file);

  return (@file_list);
}

# Print a line of output if we found a specified directive
# All matching should be case insensitive
sub output($$$)
{
  my $d = shift;
  my $l = shift;
  my $a = shift || "";
  my $directive;

  foreach $directive (@directives)
  {
    if ($directive eq "All" || $directive =~ m{^$d$}i || "\<$directive" =~ m{^$d$}i || "</$directive>" =~ m{^$d$}i)
    {
      # Verbose output is directive + argument(s)
      if ($verbose)
      {
        printf "Line %5d: ", $l  if ($print_line_no);
        printf "%s%s", "  " x $nest_level, ($d . " " . $a);
        print " " x ((50 - (2 * $nest_level) - length($d . " " . $a)) || 0) if ($print_filename);
      }
      else
      {
        printf "Line %5d: ", $l if ($print_line_no);
        printf "%s%s", "  " x $nest_level,$d;
        print " " x ((20 - (2 * $nest_level) - length($d)) || 0) if ($print_filename);
      }

      printf " ($filelist[$#filelist])" if ($print_filename);
      print "\n";
    }
  }
}

sub VERSION_MESSAGE()
{
  print <<EOM;
scanconf.pl v0.31
A program to scan through your apache configuration file(s) looking for and
reporting back on the locations of the specified directives. you must pecify
the top level configuration file (-c) or it must be able to be determined from
the \@default array. If this file does not contain the ServerRoot directive then
that must also be specified (-s).

 Usage: scanconf.pl [-q] [-v] [-s serverroot] [-c file] [directive1 directive2 ... directiven|All]
        file: path to top level httpd configuration file (i.e. httpd.conf). Required
          -c: specify path to top level configuration file
          -F: Suppress the printing the file name after each directive
          -h: Print this message
          -L: Suppress the printing of line numbers
          -s: specifiy server root as some distros use a 'default'
          -q: quiet mode, only print the 'directives' lines of output
          -v: output the full config line rather than just the directive
   directive: Any apache directive or the literal 'All' (which outputs all directives)
EOM
  exit(0);
}
