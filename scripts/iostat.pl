#!/usr/bin/env perl
# iostat.pl SNMP parser
# Mark Round, Email : cacti@markround.com
# Based heavily on the awesome Bind9 stats parser written by Cory Powers
#
# NOTE: the .1.3.6.1.3.1 OID in this script uses an "experimental" sequence,
# which may not be unique in your organisation[1]. You should probably change
# this to something else, perhaps using your own private OID.
#
# [1]=http://www.alvestrand.no/objectid/1.3.6.1.3.html
#
# USAGE
# -----
# See the README which should have been included with this file.
#
# CHANGES
# -------
# 02/09/2011 - Version 1.6-wand - Map device mapper names to pretty names by Brad Cowie
# 14/10/2010 - Version 1.6 - Added iostat-persist.pl by "asq"
# 14/10/2008 - Version 1.0 - Initial release, Linux iostat only. Solaris etc.
#                            coming in next revision!
#
# Copyright 2009 Mark Round and others. All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without modification, 
# are permitted provided that the following conditions are met:
# 
#  1. Redistributions of source code must retain the above copyright notice, 
#     this list of conditions and the following disclaimer.
#  2. Redistributions in binary form must reproduce the above copyright notice, 
#     this list of conditions and the following disclaimer in the documentation 
#     and/or other materials provided with the distribution.
# 
# THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, 
# INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND 
# FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHORS 
# OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, 
# OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE 
# GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER 
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR 
# TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS 
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

use strict;

use Carp;
use POSIX;
use File::Basename;

use constant debug => 0;
my $base_oid = ".1.3.6.1.3.1";
my $iostat_cache = "/tmp/iostat";
my $req;
my %stats;
my $devices;
my $mibtime;

# Results from iostat are cached for some seconds so that an
# SNMP walk doesn't result in collecting data over and over again:
my $cache_secs = 60;

# Switch on autoflush
$| = 1;

while (my $cmd = <STDIN>) {
  chomp $cmd;

  if ($cmd eq "PING") {
    print "PONG\n";
  } elsif ($cmd eq "get") {
    my $oid_in = <STDIN>;
    chomp $oid_in;
    process();
    getoid($oid_in);
  } elsif ($cmd eq "getnext") {
    my $oid_in = <STDIN>;
    chomp $oid_in;
    process();
    my $found = 0;
    my $next = getnextoid($oid_in);
    getoid($next);
  } else {
    # Unknown command
  }
}

exit 0;

sub process {

    # We cache the results for $cache_secs seconds
    if (time - $mibtime < $cache_secs) {
      return 'Cached';
    }

    my $uname = `/bin/uname -a`;
    my $ostype = "other";
    if ($uname =~ /SunOS/) {
       $ostype = "solaris";
    }
    if ($uname =~ /Linux/) {
       $ostype = "linux";
    }
    $devices = 1;
    open( IOSTAT, $iostat_cache )
      or return ("Could not open iostat cache $iostat_cache : $!");

    my $header_seen = 0;

    while (<IOSTAT>) {
        if (/^[D|d]evice/) {
            $header_seen++;
            next;
        }
        next if ( $header_seen < 2 );
        next if (/^$/);
        
        if ($ostype eq 'linux') { 
           /^([a-z0-9\-\/]+)\s+(\d+[\.,]\d+)\s+(\d+[\.,]\d+)\s+(\d+[\.,]\d+)\s+(\d+[\.,]\d+)\s+(\d+[\.,]\d+)\s+(\d+[\.,]\d+)\s+(\d+[\.,]\d+)\s+(\d+[\.,]\d+)\s+(\d+[\.,]\d+)\s+(\d+[\.,]\d+)\s+(\d+[\.,]\d+)/;

           my $device = $1;
           my $pretty_device;

           if ( $device =~ /^dm-\d+$/ ) {
               $pretty_device = translate_devicemapper_name($device);
           }

           $pretty_device ||= $device;

           # Brad: I really suck at perl
           /^([a-z0-9\-\/]+)\s+(\d+[\.,]\d+)\s+(\d+[\.,]\d+)\s+(\d+[\.,]\d+)\s+(\d+[\.,]\d+)\s+(\d+[\.,]\d+)\s+(\d+[\.,]\d+)\s+(\d+[\.,]\d+)\s+(\d+[\.,]\d+)\s+(\d+[\.,]\d+)\s+(\d+[\.,]\d+)\s+(\d+[\.,]\d+)/;

           $stats{"$base_oid.1.$devices"}  = $devices;			# index
           $stats{"$base_oid.2.$devices"}  = $pretty_device;	# device name
           $stats{"$base_oid.3.$devices"}  = $2;				# rrqm/s
           $stats{"$base_oid.4.$devices"}  = $3;				# wrqm/s
           $stats{"$base_oid.5.$devices"}  = $4;				# r/s
           $stats{"$base_oid.6.$devices"}  = $5;				# w/s
           $stats{"$base_oid.7.$devices"}  = $6;				# rkB/s
           $stats{"$base_oid.8.$devices"}  = $7;				# wkB/s
           $stats{"$base_oid.9.$devices"}  = $8;				# avgrq-sz
           $stats{"$base_oid.10.$devices"} = $9;				# avgqu-sz
           $stats{"$base_oid.11.$devices"} = $10;				# await
           $stats{"$base_oid.12.$devices"} = $11;				# svctm
           $stats{"$base_oid.13.$devices"} = $12;				# %util
        }

        if ($ostype eq 'solaris') {
           /^([a-z0-9\-\/]+)\s+(\d+\.\d+)\s+(\d+\.\d+)\s+(\d+\.\d+)\s+(\d+\.\d+)\s+(\d+\.\d+)\s+(\d+\.\d+)\s+(\d+\.\d+)\s+(\d)\s+(\d)/;

           $stats{"$base_oid.1.$devices"}  = $devices;     # index
           $stats{"$base_oid.2.$devices"}  = $1;           # device name
           $stats{"$base_oid.3.$devices"}  = $2;           # r/s
           $stats{"$base_oid.4.$devices"}  = $3;           # w/s
           $stats{"$base_oid.5.$devices"}  = $4;           # kr/s
           $stats{"$base_oid.6.$devices"}  = $5;           # kw/s
           $stats{"$base_oid.7.$devices"}  = $6;           # wait
           $stats{"$base_oid.8.$devices"}  = $7;           # actv
           $stats{"$base_oid.9.$devices"}  = $8;           # svc_t
           $stats{"$base_oid.10.$devices"} = $9;           # %w
           $stats{"$base_oid.11.$devices"} = $10;          # %b
        }

        $devices++;
    }

    $mibtime = time;
}

# translate_devicemapper_name
#
# Tries to find a devicemapper name based on a minor number
# Returns either a resolved LVM path or the original devicename

sub translate_devicemapper_name {
    my ($device) = @_;

    my ($want_minor) = $device =~ m/^dm-(\d+)$/;

    croak "Failed to extract devicemapper id" unless defined($want_minor);

    my $dm_major = find_devicemapper_major();
    croak "Failed to get device-mapper major number\n"
      unless defined $dm_major;

    for my $entry ( glob "/dev/mapper/\*" ) {

        my $rdev  = ( stat($entry) )[6];
        my $major = floor( $rdev / 256 );
        my $minor = $rdev % 256;

        if ( $major == $dm_major && $minor == $want_minor ) {

            my $pretty_name = translate_lvm_name($entry);

            $entry =~ s|/dev/||;

            return defined $pretty_name ? $pretty_name : $entry;
        }
    }

    # Return original string if the device can't be found.
    return $device;
}

# translate_lvm_name
#
# Translates devicemapper names to their nicer LVM counterparts
# e.g. /dev/mapper/VGfoo-LVbar -> /dev/VGfoo/LVbar

sub translate_lvm_name {

    my ($entry) = @_;

    my $device_name = basename($entry);

# Check for single-dash-occurence to see if this could be a lvm devicemapper device.
    if ( $device_name =~ m/(?<!-)-(?!-)/ ) {

        # split device name into vg and lv parts
        my ( $vg, $lv ) = split /(?<!-)-(?!-)/, $device_name, 2;
        return unless ( defined($vg) && defined($lv) );

        # remove extraneous dashes from vg and lv names
        $vg =~ s/--/-/g;
        $lv =~ s/--/-/g;

        $device_name = "$vg/$lv";

        # Sanity check - does the constructed device name exist?
        # Breaks unless we are root.
        if ( stat("/dev/$device_name") ) {
            return "$device_name";
        }

    }
    return;
}

# find_devicemapper_major
#
# Searches for the major number of the devicemapper device

sub find_devicemapper_major {

    my $devicefh;

    open( $devicefh, '<', '/proc/devices' )
      or croak "Failed to open '/proc/devices': $!";

    my $dm_major;

    while ( my $line = <$devicefh> ) {
        chomp $line;

        my ( $major, $name ) = split /\s+/, $line, 2;

        next unless defined $name;

        if ( $name eq 'device-mapper' ) {
            $dm_major = $major;
            last;
        }
    }
    close($devicefh);

    return $dm_major;
}

sub getoid {
    my $oid = shift(@_);
    print "Fetching oid : $oid\n" if (debug);
    if ( $oid =~ /^$base_oid\.(\d+)\.(\d+).*/ && exists( $stats{$oid} ) ) {
        print $oid. "\n";
        if ( $1 == 1 ) {
            print "integer\n";
        }
        else {
            print "string\n";
        }
        print $stats{$oid} . "\n";
    } else {
      print "NONE\n";
    }
}

sub getnextoid {
    my $first_oid = shift(@_);
    my $next_oid  = '';
    my $count_id;
    my $index;

    if ( $first_oid =~ /$base_oid\.(\d+)\.(\d+).*/ ) {
        print("getnextoid($first_oid): index: $2, count_id: $1\n") if (debug);
        if ( $2 + 1 >= $devices ) {
            $count_id = $1 + 1;
            $index    = 1;
        }
        else {
            $index    = $2 + 1;
            $count_id = $1;
        }
        print(
            "getnextoid($first_oid): NEW - index: $index, count_id: $count_id\n"
        ) if (debug);
        $next_oid = "$base_oid.$count_id.$index";
    }
    elsif ( $first_oid =~ /$base_oid\.(\d+).*/ ) {
        $next_oid = "$base_oid.$1.1";
    }
    elsif ( $first_oid eq $base_oid ) {
        $next_oid = "$base_oid.1.1";
    }
    else {
        $next_oid = "$base_oid.1.1";
    }
    print("getnextoid($first_oid): returning $next_oid\n") if (debug);
    return $next_oid;
}
