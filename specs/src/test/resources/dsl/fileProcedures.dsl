project "ECSpec", {
    procedure "Files", {
        step 'Files', {
            shell = 'ec-perl'
            command = '''
#
#  Copyright 2015 Electric Cloud, Inc.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#

use ElectricCommander;
use ElectricCommander::PropDB;

$::ec = new ElectricCommander();
$::ec->abortOnError(0);

$|=1;
use strict;
use warnings;

my $files  = \'$[files]\' or die "file is required";
my $action     = \'$[action]\' or die "Action is required";
my $basedir = \'$[basedir]\';
my $propResult = \'$[propResult]\';
$basedir       = defined $basedir ? $basedir . '/' : ''; # // is not supported in perl 5.8.8
$propResult    = '/myJob/result' unless $propResult; # // is not supported in perl 5.8.8

my $content;

if ($action eq 'write') {
    $content = \'$[content]\' or die "Content not given";
}


while ($files =~ /^(.+)$/gm) {
    my $file = $1;
    my $path = $basedir . $file;
    my $result;
    if ($^O eq 'MSWin32'){
        $path =~ s/\\//\\\\/g;
        print "Substituted path to: $path\\n";
    }
    if ($action eq 'readable') {
        $result = -r $path ? 1 : 0;
    } elsif ($action eq 'read') {
        if (-f $path and -r $path and open (my $fh, '<', $path)) {
            local $/=undef;
            $result = <$fh>;
            close $fh;
        } elsif (-d $path and -r $path and opendir(my $dh, $path)) {
            $result = join "\n", readdir($dh);
        }

    } elsif ($action eq 'write') {
        if (open (my $fh, '>', $path)) {
            $result = print $fh $content;
            close $fh;
        }
    } else {
        die "Invalid action: $action";
    }
    if (defined $result) {
        print "Registering results for $file in $propResult : $result\n";
        $::ec->setProperty($propResult . '/' . $file, $result);
    } else {
        print "No results for $file\n";
    }
}
'''
        }

        formalParameter 'files', defaultValue: '', {
            type = "textarea"
        }

        formalParameter 'action', defaultValue: '', {
            type = "entry"
        }

        formalParameter 'basedir', defaultValue: '', {
            type = "entry"
        }

        formalParameter 'propResult', defaultValue: '', {
            type = "entry"
        }

        formalParameter 'content', defaultValue: '', {
            type = "textarea"
        }
    }
}

