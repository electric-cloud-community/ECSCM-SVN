####################################################################
#
# ECSCM::SVN::Driver  Object to represent interactions with 
#        SVN.
####################################################################
package ECSCM::SVN::Driver;
@ISA = (ECSCM::Base::Driver);
use ElectricCommander;
use Time::Local;
use XML::XPath;
use Getopt::Long;
use Cwd;
use File::Spec;
use File::Path;

$|=1;

if (!defined ECSCM::Base::Driver) {
    require ECSCM::Base::Driver;
}

if (!defined ECSCM::SVN::Cfg) {
    require ECSCM::SVN::Cfg;
}

####################################################################
# Object constructor for ECSCM::SVN::Driver
#
# Inputs
#    cmdr          previously initialized ElectricCommander handle
#    name          name of this configuration
#                 
####################################################################
sub new {
    my ($this, $cmdr, $name) = @_;
    my $class = ref($this) || $this;

    my $cfg = new ECSCM::SVN::Cfg($cmdr, "$name");
    my $pluginKey = undef;
    
    if ($name ne "") {
        $pluginKey = $cfg->getSCMPluginName();
        if ($pluginKey ne "ECSCM-SVN") { die "SCM config $name is not type ECSCM-SVN"; }
    }

    my ($self) = new ECSCM::Base::Driver($cmdr,$cfg);

    # Force svn output to be in english
    $ENV{LANG}="en_US.UTF-8";
    
    my $xpath = $cmdr->getPlugin($pluginKey);
    my $pluginName = $xpath->findvalue('//pluginVersion')->value;
    print "\nUsing plugin $pluginKey version $pluginName\n";

    bless ($self, $class);
    return $self;
}

####################################################################
# isImplemented
####################################################################
sub isImplemented {
    my ($self, $method) = @_;
    
    if ($method eq 'getSCMTag' || 
        $method eq 'checkoutCode' || 
        $method eq 'apf_driver' || 
        $method eq 'cpf_driver') {
        return 1;
    } else {
        return 0;
    }
}

####################################################################
# get scm tag for sentry (continuous integration)
####################################################################

####################################################################
# getSCMTag
# 
# Get the latest changelist on this branch/client
#
# Args:
# Return: 
#    changeNumber - a string representing the last change sequence #
#    changeTime   - a time stamp representing the time of last change     
####################################################################
sub getSCMTag {
    my ($self, $opts) = @_;

    # add configuration that is stored for this config
    my $name = $self->getCfg()->getName();
    my %row = $self->getCfg()->getRow($name);
    foreach my $k (keys %row) {
        $self->debug("Reading $k=$row{$k} from config");
        $opts->{$k}="$row{$k}";
    }

    # Load userName and password from the credential
    ($opts->{svnUserName}, $opts->{svnPassword}) = 
        $self->retrieveUserCredential($opts->{credential}, 
        $opts->{svnUserName}, $opts->{svnPassword});

    if (length ($opts->{repository}) == 0) {
        $self->issueWarningMsg ("No Subversion Repository was specified.");
        return (undef,undef);
    }
    
    my $passwordStart = 0;
    my $passwordLength = 0;
    my $revisionNumber = undef;
    my $revisionTimeString = "";
    my $changeTimestamp;
    my $currentTimestamp;
    
    #Check the SVN version. Before 1.5, it doesn't allow --non-interactive
    my $svnCommand = qq|${\($self->getSVNCommand())} --version --quiet|;

    my $cmndReturn = $self->RunCommand($svnCommand, {LogCommand => 1, LogResult => 0 } );
    $cmndReturn =~ /version (\d+).(\d+)/;
    my $options = qq| --xml|;
    if(1 <= $1 && 5 <= $2){
        $options .= qq| --non-interactive|;
    }
    if(1 <= $1 && 6 <= $2){
        $options .= qq| --trust-server-cert|;
    }

    #manage multiple repositories
    my $nDepots = 0;
    my @lines = split(/\n/, $opts->{repository});
    foreach my $line (@lines) {
        # set the generic svn command
        $svnCommand = qq|${\($self->getSVNCommand())} info "$line" | . $options;
    
        # add the options
        $svnCommand .= " --username $opts->{svnUserName}" if (length ($opts->{svnUserName}) > 0);
        if (length ($opts->{svnPassword}) > 0) {
            $svnCommand .= " --password ";
            $passwordStart = length $svnCommand;
            $svnCommand .= "$opts->{svnPassword}";
            $passwordLength = (length $svnCommand) - $passwordStart;
        }
    
        # run Subversion
        $cmndReturn = $self->RunCommand("$svnCommand", 
                {LogCommand => 1, LogResult => 1, HidePassword => 1,
                passwordStart => $passwordStart, 
                passwordLength => $passwordLength } );
    
        # Extract the changeset number and the date and time components
        # XML response looks like:
        #   <?xml version="1.0"?>
        #     <info>
        #       <entry
        #          kind="dir"
        #          path="trunk"
        #          revision="12">
        #         <url>file:///c:/svn-repos/SampleApp/trunk</url>
        #         <repository>
        #           <root>file:///c:/svn-repos</root>
        #           <uuid>4b23f0d2-66c8-144e-84b7-b5ef7e203074</uuid>
        #         </repository>
        #         <commit
        #            revision="10">
        #           <author>eli</author>
        #           <date>2007-10-25T00:20:04.701942Z</date>
        #         </commit>
        #       </entry>
        #     </info>
        #
        # An error response looks like:
        #   <?xml version="1.0"?>
        #   <info>
        #   </info>
        #   file:\\\c:\svn-repos\SampleApp\branches\B9.9:  (Not a valid URL)
        #  Make sure the response is legal XML
        #       It must contain a </info> tag
        #       We need to remove error info after the </info> tag
        
        
        my $xmlPortion = $cmndReturn;
        if ($xmlPortion =~ s/(?<=<\/info>).*/\n/s) {
         
            my $xPath = XML::XPath->new(xml => $xmlPortion);
            if(0 < $nDepots){
                $revisionNumber .= ',';
            }
            $revisionNumber .= $xPath->findvalue('/info/entry/commit/@revision');
            $revisionTimeString = $xPath->findvalue('/info/entry/commit/date');
            #if there are more depots, add a , at the beginnig of the value
            $nDepots++;
        }
    
        # Get the timestamp for the revision (UTC time)
        #     2007-10-16T04:31:32.281250Z
        
        if (length $revisionTimeString >0) { 
            $revisionTimeString =~ '([\d]+)-([\d]+)-([\d]+)T([\d]+):([\d]+):([\d]+)';
            #                          sec min hr  day mon   yr
            $currentTimestamp =  timegm($6, $5, $4, $3, $2-1, $1-1900);
            if($changeTimestamp < $currentTimestamp) {
                $changeTimestamp = $currentTimestamp;
            }
        }
    } 

    if(length($opts->{Revision_outpp})) {
        $self->getCmdr()->setProperty($opts->{Revision_outpp}, $revisionNumber);
    }
    
    return ($revisionNumber, $changeTimestamp);
}



####################################################################
# checkoutCode
#
# Results:
#   Uses the "svn checkout" command to checkout code to the workspace.
#   Collects data to call functions to set up the scm change log.
#
# Arguments:
#   self -              the object reference
#   opts -              A reference to the hash with values
#
# Returns
#   Output of the the "svn checkout" command.
#
####################################################################
sub checkoutCode
{
    my ($self,$opts) = @_;
    
    # add configuration that is stored for this config
    my $name = $self->getCfg()->getName();
    my %row = $self->getCfg()->getRow($name);
    foreach my $k (keys %row) {
        $opts->{$k}=$row{$k};
    }

    $self->setSVNCommand($opts->{command});
    
    # Load userName and password from the credential
    ($opts->{SVNUSER}, $opts->{SVNPASSWD}) = 
        $self->retrieveUserCredential($opts->{credential}, $opts->{SVNUSER}, $opts->{SVNPASSWD});
    
    if (! (defined $opts->{dest})) {
        warn "dest argument required in checkoutCode";
        return;
    }
    
    if((defined $opts->{CheckoutType} && $opts->{CheckoutType} eq "F") && (defined $opts->{FileName} && $opts->{FileName} eq "")) {
        warn "You must provide the file you want to download when using the file checkout option";
        return;
    }
    
    # Check the SVN version. Before 1.5, it doesn't allow --non-interactive
    my $svnCommand = qq|${\($self->getSVNCommand())} --version|;
    my $cmndReturn = $self->RunCommand($svnCommand, {LogCommand => 1, LogResult => 0 } );
    $cmndReturn =~ /version (\d+).(\d+)/;
    my $options = '';
    if(defined $opts->{IgnoreExternals} && $opts->{IgnoreExternals} eq "1"){
        $options .= qq| --ignore-externals|;
    }
    if(1 <= $1 && 5 <= $2){
        $options .= qq| --non-interactive|;
    }
    if(1 <= $1 && 6 <= $2){
        $options .= qq| --trust-server-cert|;
    }
    # add an option for the file checkout
    if(defined $opts->{CheckoutType} && $opts->{CheckoutType} eq "F"){
        $options .= qq| --depth empty|;
    }
    
    my $command = "";
    my $result = "";
    my $passwordStart = 0;
    my $passwordLength = 0;
    
    #checkout multiple depots
    my @svnURLs = split(/\|/, $opts->{SubversionUrl});
    my $size = @svnURLs;
	my $ec = $self->getCmdr();
	
    # When multiple paths are given in format "path1|path2|...", revision of these paths could aslo be given in format "rev1|rev2|...".
    # This is also how this plugin record revisons checked out in file ecpreflight_data/scmInfo
	my @svnRevisions = ();
	if (defined $opts->{SubversionRevision} && $opts->{SubversionRevision} ne "" ) {
	    @svnRevisions = split(/\|/, $opts->{SubversionRevision});
	}
	
    foreach my $url (@svnURLs) {
        my $subdir = $opts->{dest};
        if($size ne 1) {
            $url =~ /(.*)\/(.*)/;
            $subdir .= qq{/$2};
        }
        
        if (substr($subdir,-1,1) eq "\\"){
            chop($subdir);
        }
        
        $command = qq{${\($self->getSVNCommand())} checkout "$url" "$subdir" $options};
        $passwordStart = 0;
        $passwordLength = 0;

		# only add revision parameter in case revision is given by user or fetched from file ecpreflight_data/scmInfo
        my $revision = shift(@svnRevisions);
        if (length($revision)) {
			$command .= " --revision $revision";
        }

        if (length ($opts->{SVNUSER})) {
            $command .= qq| --username=$opts->{SVNUSER}|;
            $passwordLength = length $opts->{SVNPASSWD};
            if ($passwordLength) {
                $command .= qq| --password=|;
                $passwordStart = length $command;
                $command .= qq|$opts->{SVNPASSWD}|;
            }
        }
    
        $result = $self->RunCommand($command, {
            LogCommand => 1,
            LogResult => 1,
            HidePassword => 1,
            passwordStart => $passwordStart,
            passwordLength => $passwordLength
        });
        
        # extra commmand for file checkout
        if(defined $opts->{CheckoutType} && $opts->{CheckoutType} eq "F"){
            my $here = getcwd();
            $opts->{dest} = File::Spec->rel2abs($opts->{dest});
            print "Changing to directory $opts->{dest}\n";
            mkpath($opts->{dest});
            if (!chdir $opts->{dest}) {
                print "could not change to directory $opts->{dest}\n";
                exit 1;
            }
            my @files = split(/\|/, $opts->{FileName});
            my $fileList = "";
            foreach my $file (@files){
                $fileList .= qq{"$file" };
            }
            my $updateFileCommand = qq{${\($self->getSVNCommand())} up $fileList};
            
            $result .= "\n" . $self->RunCommand("$updateFileCommand", {
			    LogCommand => 1,
				LogResult => 1
		    });
            
            chdir $here;
        }
    
    
        # Parse $result and grab the checked out revision from the last line.
        # Example of the last line of output from a checkout command:
        #
        # Checked out revision 1.
        #
        
        $result =~ m/Checked out revision ([\d]+)./;
        my $toRevision = $1;
    
        if (!$toRevision || $toRevision eq "") {
            # log that we were not able to determine the current revision
            return $result;
        }
    
        my $scmKey = $self->getKeyFromUrl($url);

		# Retrieve revision of latest snapshot
        my $fromRevision = $self->getLastSnapshotId($scmKey);
	    
        if ($fromRevision eq "") {
            $fromRevision = $toRevision;
        } elsif ($fromRevision > 1) {
            # ECPSCMSUBVERSION-54 : Increment the fromRevision so we do not
            # report this revision twice (this run's $toVersion becomes next run's $fromVersion)
            $fromRevision++;
        }
        
		#Generate the report output from XML
        my $changeLog = $self->getChangeLog($url, $fromRevision, $toRevision, $opts);
        				
		my $xPath = XML::XPath->new(xml => $changeLog);
            
        my $logSet = $xPath->find('log/logentry');
				
		my $tmp_changelog = q{};
								
		foreach my $logNode ($logSet->get_nodelist) {			
			my $revision = $logNode->findvalue('@revision');			
			my $author = $logNode->findvalue('author');
			my $date = $logNode->findvalue('date');
			my $msg = $logNode->findvalue('msg');
			
			$tmp_changelog .= qq{Revision: $revision\n Log Message: $msg\n Author: $author\n Date: $date\n\n};	
			my $pathSet = $xPath->find('paths/path', $logNode);
			
		
			foreach my $pathNode ($pathSet->get_nodelist){
			    
				my $kind = $pathNode->findvalue('@kind');
				my $action = $pathNode->findvalue('@action');
				my $path = $pathNode->string_value;	
                
				$tmp_changelog .= qq{		Kind: $kind Action: $action Path: $path \n};              				
			}		      
        }
		    
		$changeLog = $tmp_changelog;
		
		$self->setPropertiesOnJob($scmKey, $toRevision, $changeLog, $url);
		
        if($opts->{Revision_outpp} && $opts->{Revision_outpp} ne ""){
            $ec->setProperty($opts->{Revision_outpp}, $toRevision);
        }
        
		my ($projectName, $scheduleName, $procedureName) = $self->getProjectAndScheduleNames();
		
		if ($scheduleName ne ""){
			my $prop = "/projects[$projectName]/schedules[$scheduleName]/ecscm_changelogs/$scmKey";			
			$ec->setProperty($prop, $changeLog);
		}
    }
	
	$self->createLinkToChangelogReport("Changelog Report");

    return $result;
}

# Traverse path up searching for .svn directory
# If directory found, return 1
sub validSvnRepo {
    my ($self, $path) = @_;
    
    my @dirs = File::Spec->splitdir(File::Spec->rel2abs($path));

    for(my $i = scalar(@dirs) - 1; $i > 0; $i--)
    {
        my @dir = @dirs[0 .. $i];
        push(@dir, ".svn");
        return 1 if (-d File::Spec->catdir(@dir));
    }

    return 0;
}

sub updateRepo{
    my ($self,$opts) = @_;
    
    # add configuration that is stored for this config
    my $name = $self->getCfg()->getName();
    my %row = $self->getCfg()->getRow($name);
    
    foreach my $k (keys %row) {
        $opts->{$k}=$row{$k};
    }
    
    my $local_dir = $opts->{dest};
    $self->setSVNCommand($opts->{command});
    
    if(!($self->validSvnRepo($local_dir))){
        #local directory is not a valid svn repository copy
        print qq{Directory "$local_dir" is not a valid svn repository copy};
        exit 1;
    }
    
    my $cmd = qq{${\($self->getSVNCommand())} update "$local_dir"};
    
    if($opts->{revision}){
        $cmd .= " --revision $opts->{revision}";
    }
    
    #non interactive mode to prevent hangs
    $cmd .= " --non-interactive";
    
    my ($user, $password) = $self->retrieveUserCredential($opts->{credential});
    
    $cmd .= " --username $user" if ($user);
    $cmd .= " --password $password" if($password);
    
    my $start;
    my $end;

    $cmd =~ /--password\s(.*)/;
    #catch regex indexes
    $start = $-[0]+length("--password ");
    $end = length($password);
    
    $self->RunCommand($cmd, {LogCommand=>1, HidePassword => 1, passwordStart => $start, passwordLength => $end});
    
}

sub commitChanges{
    my ($self,$opts) = @_;
    
    # add configuration that is stored for this config
    my $name = $self->getCfg()->getName();
    my %row = $self->getCfg()->getRow($name);
    
    foreach my $k (keys %row) {
        $opts->{$k}=$row{$k};
    }

    $self->setSVNCommand($opts->{command});
    
    # Load userName and password from the credential
    ($opts->{SVNUSER}, $opts->{SVNPASSWD}) = 
        $self->retrieveUserCredential($opts->{credential}, $opts->{SVNUSER}, $opts->{SVNPASSWD});
        
    if (!chdir $opts->{svnDirectory}) {
        print "could not change to directory $opts->{svnDirectory}\n";
        exit 1;
    }
    
    my $passwordStart;
    my $passwordLength;
    my $command = qq{${\($self->getSVNCommand())} commit };
    if($opts->{CommitMessage} && $opts->{CommitMessage} ne ""){
        $command .= qq{-m "$opts->{CommitMessage}" };
    }
    
    if (length ($opts->{SVNUSER}) > 0) {
            $command .= qq| --username=$opts->{SVNUSER}|;
            $passwordLength = length $opts->{SVNPASSWD};
            if ($passwordLength) {
                $command .= qq| --password=|;
                $passwordStart = length $command;
                $command .= qq|$opts->{SVNPASSWD}|;
            }
        }
    
    my $result = $self->RunCommand($command, {LogCommand=>1, HidePassword => 1, passwordStart => $passwordStart,
                        passwordLength => $passwordLength});
}
    

####################################################################
# getChangeLog
#
# Side Effects:
#   
# Arguments:
#   self -              the object reference
#   url  -              the Subversion url
#   fromRevision -      the "from" argument to "svn log"
#   toRevision -        the "to" argument to "svn log"
#
# Returns:
#   Returns the output of the "svn log" command.
#
####################################################################
sub getChangeLog
{
    my ($self, $url, $fromRevision, $toRevision, $opts) = @_;
    
    #Check the SVN version. Before 1.5, it doesn't allow --non-interactive
    my $svnCommand = qq|${\($self->getSVNCommand())} --version|;
    my $cmndReturn = $self->RunCommand("$svnCommand", {LogCommand => 0, LogResult => 0 } );
    $cmndReturn =~ /version (\d+).(\d+)/;
    my $options = qq| --xml -v|;
    if(1 <= $1 && 5 <= $2){
        $options .= qq| --non-interactive|;
    }
    if(1 <= $1 && 6 <= $2){
        $options .= qq| --trust-server-cert|;
    }
	# If 'from' is more than 'to' then make them the same.  This can happen if
	# for example a previous checkout was done to revision 90 and a subsequent
	# checkout was called explicitly for revision 89.
	if ($fromRevision > $toRevision) {
		$fromRevision = $toRevision;	
	}
    my $command = qq|${\($self->getSVNCommand())} log \"$url\" -r $fromRevision:$toRevision| . $options;
    
	my ($passwordStart, $passwordLength) = 0;
	if (length ($opts->{SVNUSER}) > 0) {
           $command .= qq| --username=$opts->{SVNUSER}|;
           $passwordLength = length $opts->{SVNPASSWD};
           if ($passwordLength) {
               $command .= qq| --password=|;
               $passwordStart = length $command;
               $command .= qq|$opts->{SVNPASSWD}|;
           }
       }

    my $result = $self->RunCommand($command, {
        LogCommand => 1,
        HidePassword => 1,
        LogResult => 0,
        passwordStart => $passwordStart,
        passwordLength => $passwordLength
    });

    return $result;
}

####################################################################
# getKeyFromUrl
#
# Side Effects:
#
# Arguments:
#   url  -              the Subversion url
#
# Returns:
#   "Subversion" prepended to the url with all / replaced by colon
####################################################################
sub getKeyFromUrl
{
    my ($self, $url) = @_;
    $url =~ s/\//:/g;
    return "Subversion-$url";
}

####################################################################
# getUrlFromKey
#
# Side Effects:
#   
# Arguments:
#   key  -              a key in a property sheet
#
# Returns:
#   A Subversion url
####################################################################
sub getUrlFromKey
{
    my ($self, $key) = @_;
    $key =~ s/^Subversion-//;
    $key =~ s/__slash__/\//g;
    return $key;
}

####################################################################
# agent preflight functions
####################################################################

#------------------------------------------------------------------------------
# apf_getScmInfo
#
#       If the client script passed some SCM-specific information, then it is
#       collected here.
#------------------------------------------------------------------------------

sub apf_getScmInfo
{
    my ($self,$opts) = @_;
        
    my $scmInfo = $self->pf_readFile("ecpreflight_data/scmInfo");
    $scmInfo =~ m/(.*)\n(.*)\n(.*)\n(.*)\n(.*)\n/;
    $opts->{SubversionUrl} = $1;
    $opts->{SubversionRevision} = $2;
    $opts->{SubversionUpdateToHead} = $3;
    $opts->{SubversionIgnoreExternals} = $4;
    $opts->{SubversionChangelist} = $5;

    print("Subversion information received from client:\n"
            . "Subversion URL: $opts->{SubversionUrl}\n"
            . "Revision: $opts->{SubversionRevision}\n\n");

    if ($opts->{SubversionChangelist}) {
        print "Agent workspace will be updated for specified changelist: $opts->{SubversionChangelist}\n";
    }

    if ($opts->{SubversionUpdateToHead}) {
        $opts->{SubversionRevision} = "HEAD";
        print "Agent workspace will be updated to: $opts->{SubversionRevision}\n";
    } else {
        print "Agent workspace will be updated to the same revision as the client: $opts->{SubversionRevision}\n";
    }

    if ($opts->{SubversionIgnoreExternals}) {
        print "Any svn externals properties will be ignored\n";
    } else {
        print "svn externals properties will be handled\n";
    }
}

#------------------------------------------------------------------------------
# apf_createSnapshot
#
#       Create the basic source snapshot before overlaying the deltas passed
#       from the client.
#------------------------------------------------------------------------------

sub apf_createSnapshot
{
    my ($self,$opts) = @_;
    my $local_dir = $opts->{dest};
    if($opts->{update} && $opts->{update} eq "1"){
        #check if $local_dir is a valid svn repository
        if(($self->validSvnRepo($local_dir))){
            #update only when possible
            $self->updateRepo($opts);
        }else{
            $self->checkoutCode($opts);
        }
    }else{
        $self->checkoutCode($opts);
    }
}

#------------------------------------------------------------------------------
# apf_handleExternalsProperties
#
#           Set up svn:externals properties if necessary.
#
#------------------------------------------------------------------------------

sub apf_handleExternalsProperties
{
    my ($self,$opts) = @_;
    
    my $file = File::Spec->catfile($opts->{StartDir}, "ecpreflight_data", "externalsProperty");

    if ( ! -f $file) {
        print "File $file does not exist, so no svn:externals properties to set up\n";
        return;
    } else {
        print "Setting up svn:externals properties...\n";
    }

    my $dir = File::Spec->catdir($opts->{StartDir}, $opts->{dest});
    chdir($dir);

    # Process file externalsProperty
    my $command = "";
    my $res = "";

    my @lines = split(/\n/, $self->pf_readFile($file));
    my $count = 0;
    foreach (@lines) {
        chomp($_);
        if( $_ ne "" ) {
            print "Directory being processed is: $_\n";

            $command = "${\($self->getSVNCommand())} propget svn:externals $_";
            $res = $self->RunCommand($command, {LogCommand=>1});
            print "Command:\n$command\nHad the following output:\n$res\n\n";
            my @targets = split(/\n/, $res);
            my @dirs = ();
            foreach (@targets) {
                split ' ', $_;
                push @dirs, @_[0];
            }

            $file = File::Spec->catfile($opts->{StartDir}, "ecpreflight_data", $count);

            if ( -f $file && ! -z $file ) {
                print "setting property svn:externals for $_...\n";
                $command = "${\($self->getSVNCommand())} propset svn:externals -F $file $_";
                $res = $self->RunCommand($command, {LogCommand => 1});
                print "Command:\n$command\nHad the following output:\n$res\n\n";
            } else {
                print "deleting property svn:externals for $_...\n";
                $command = "${\($self->getSVNCommand())} propdel svn:externals $_";
                $res = $self->RunCommand($command, {LogCommand=>1});
                print "Command:\n$command\nHad the following output:\n$res\n\n";

                # should we delete the associated directories as well (in @dirs)?

            }
            print "Running update on command on $_ to bring in new svn:externals properties\n";
            $command = "${\($self->getSVNCommand())} update $_";
            $res = $self->RunCommand($command, {LogCommand=>1});
            print "Command:\n$command\nHad the following output:\n$res\n\n";
        }
        $count++;
    }

    chdir($opts->{StartDir});
}

#------------------------------------------------------------------------------
# apf_handleExternalsRevisions
#
#           Update svn:externals revisions if necessary
#
#------------------------------------------------------------------------------

sub apf_handleExternalsRevisions
{
    my ($self,$opts) = @_;
    # If the agent workspace should be udpated to head, nothing to do
    if ($opts->{SubversionUpdateToHead}) {
        print "Keeping svn:externals directories at present revision\n";
        return;
    } else {
        print "Going to update each svn:externals directory to revision found on client...\n";
    }

    my $file = "";
    $file = File::Spec->catfile($opts->{StartDir}, "ecpreflight_data", "externalsRev");

    if ( ! -f $file) {
        print "File $file does not exist, so not updating the revisions of svn:externals properties\n";
        return;
    }

    my $dir = File::Spec->catdir($opts->{StartDir}, $opts->{dest});
    chdir($dir);

    # Process file externalsRev
    my $command = "";
    my $res = "";

    my @lines = split(/\n/, $self->pf_readFile($file));
    foreach (@lines) {
        chomp($_);
        if( $_ ne "" ) {
            # split at the first space
            split ' ', $_;
            my $rev = @_[0];
            my $ext = @_[1];

            print "Attempting to update directory $ext to revision $rev\n";

            $command = "${\($self->getSVNCommand())} update -r$rev $ext";
            $res = $self->RunCommand($command, {LogCommand => 1});
            print "Command:\n$command\nHad the following output:\n$res\n\n";
        }
    }

    chdir($opts->{StartDir});
}

#------------------------------------------------------------------------------
# driver
#
#       Main program for the application.
#------------------------------------------------------------------------------

sub apf_driver()
{
    my ($self,$opts) = @_;
    
    if ($opts->{test}) { $self->setTestMode(1); }
        $opts->{delta} = "ecpreflight_files";

    $opts->{StartDir} = File::Spec->curdir(); 
    
    if (!File::Spec->file_name_is_absolute($opts->{StartDir})) {
        $opts->{StartDir} = File::Spec->rel2abs($opts->{StartDir});
    }
	
	if ($opts->{dest} eq "") {
	    $opts->{dest} = $opts->{StartDir};
	}

    $self->apf_downloadFiles($opts);
    $self->apf_transmitTargetInfo($opts);
    $self->apf_getScmInfo($opts);
    $self->apf_createSnapshot($opts);

    if ( ! $opts->{SubversionIgnoreExternals}) {
        $self->apf_handleExternalsProperties($opts);
        $self->apf_handleExternalsRevisions($opts);
    } 

    $self->apf_deleteFiles($opts);
	$self->apf_overlayDeltas($opts);
}


####################################################################
# client preflight file
####################################################################

#------------------------------------------------------------------------------
# svn
#
#       Runs an svn command.  Also used for testing, where the requests and
#       responses may be pre-arranged.
#------------------------------------------------------------------------------
sub cpf_svn {
    my ($self,$opts, $command, $options) = @_;
    if ($opts->{scm_path} ne "") {
        $command .= " \"" . $opts->{scm_path} . "\"";
    }
    #Check the SVN version. Before 1.5, it doesn't allow --non-interactive
    my $svnCommand = qq|${\($self->getSVNCommand())} --version|;
    my $cmndReturn = $self->RunCommand("$svnCommand", {LogCommand => 0, LogResult => 0 } );
    $cmndReturn =~ /version (\d+).(\d+)/;
    my $additionalOptions = "";
    if(1 <= $1 && 5 <= $2){
        $additionalOptions .= qq| --non-interactive|;
    }
    if(1 <= $1 && 6 <= $2){
        $additionalOptions .= qq| --trust-server-cert|;
    }
    $self->cpf_debug("Running Subversion command \"$command\"");
    if ($opts->{opt_Testing}) {
        my $request = uc("svn_$command");
        $request =~ s/[^\w]//g;
        if (defined($ENV{$request})) {
            return $ENV{$request};
        } else {
            $self->cpf_error("Pre-arranged command output not found in ENV");
        }
    } else {
        return $self->RunCommand("${\($self->getSVNCommand())} $command $additionalOptions", $options);
    }
}

#------------------------------------------------------------------------------
# copyDeltas
#
#       Finds all new and modified files, and calls putFiles to upload them
#       to the server.
#------------------------------------------------------------------------------
sub cpf_copyDeltas()
{
    my ($self,$opts) = @_;
    
    $self->cpf_display("Collecting delta information");

    $self->cpf_saveScmInfo($opts,
        $opts->{scm_url} ."\n"
      . $opts->{scm_lastchange} ."\n"
      . $opts->{scm_updatetohead} ."\n"
      . $opts->{scm_ignoreexternals} ."\n"
      . $opts->{svn_changelist} ."\n"); 

    $self->cpf_findTargetDirectory($opts);
    $self->cpf_createManifestFiles($opts);
    
    my $status = "";
    my $log = "";
    my $numFiles = 0;
    my %externalsRevs = ();
    
    # Collect a list of opened files.
    my @svnPaths = split(/\|/, $opts->{scm_multiple_path});
    
    my $size = @svnPaths;
    foreach my $path (@svnPaths) {
        
        $opts->{scm_path} = $path;
        my $path = $opts->{scm_path};
        my $credentials = "";
        my $statusCmd   = "status " .$opts->{scm_ignoreexternals} ." --show-updates --verbose";
        my $infoCmd     = "info";
		$path =~ s/\\/\\\\/g;
		if ($self->isWindows()){
		   $path =~ s/\//\\\\/g;
		}
		
        #add credential to both commands if available
        $credentials .= " --username $opts->{svnUserName}" if (length ($opts->{svnUserName}) > 0);
        $credentials .= " --password $opts->{svnPassword} " if (length ($opts->{svnPassword}) > 0);

        $statusCmd .= $credentials if  $credentials ne "";
        $infoCmd   .= $credentials if  $credentials ne "";

        # List only changes in specified SVN changelist
        if(length($opts->{svn_changelist})) {
            my $clopt = " --changelist $opts->{svn_changelist}";
            $statusCmd .= $clopt;
            $infoCmd .= $clopt;
        }
        
        $status = $self->cpf_svn($opts, $statusCmd, {LogCommand => 0, LogResult => 0});
        $log = $self->cpf_svn($opts, $infoCmd, {LogCommand => 0, LogResult => 0});
        $log =~ m/URL: (.*)\/(.*)/;
        my $urlDest = $2;
        
        foreach my $line(split(/\n/, $status)) {
            # Parse the output from svn opened and figure out the file name and
            # what type of change is being made.
            
            my ($type, $dest, $source);
			if ($line =~ m/^(.).*$path[\/|\\](.*)/i) {
                $type = $1;
                $dest = $2; 

                if($line =~ /  \+/) {
                    $type = "A";
                }
                
                next if ($1 eq " " || $1 eq "?" || $1 eq "!" || $1 eq "X");
                
                if ($line =~ m/^Performing status on external item at /) {
                    # This is an external directory, collect revision information
                    # about it.
    
                    # extract the relative path
    
                    my $relPath = $line;
                    my $scmPath =$opts->{scm_path}; # to make next line easier
                    $relPath =~ s/^Performing status on external item at \'$scmPath//;
    
                    # strip off any leading slashes
                    $relPath =~ s/^\///;
    
                    $relPath =~ s/\'$//;
    
                    # Do "svn info $relPath" to get the rev of this external
                    # Don't use svn subroutine since it appends the path to the command to get
                    # absolute paths when we need relative paths here.
                    my $infoOut = $self->RunCommand("${\($self->getSVNCommand())} info $relPath");
    
                    my $rev = "";
                    my @infoOutLines = split(/\n/, $infoOut);
                    foreach my $l (@infoOutLines) {
                        if ($l =~ m/Last Changed Rev: ([\d]+)/) {
                            $rev = $1;
                            $self->cpf_debug("Directory $relPath is at revision: $rev");
                            if ($rev && $rev ne "") {
                                $externalsRevs{$relPath} = $rev;
                            }
                            last;
                        }
                    }
                    next;
                }
                
                $source = File::Spec->catfile($opts->{scm_path}, $dest);
                #remove space character
                $urlDest =~ s/\%20/ /g;
                my $length = length($urlDest) - 1;
                my $lastChar = substr($urlDest, $length);
                if($lastChar ne '/' ) {
                        $urlDest .= '/';
                }
                if($size ne 1) {
                    $dest = $urlDest . $dest;
                }
                if (-d $source) {
                    next;
                }
                if ($type eq "C") {
                    $self->cpf_error("Opened file \"$source\" has unresolved conflicts. "
                            . "Resolve conflicts, then retry the preflight build");
                }
                if ($line =~ m/$type[ ]+\*[ ]+[\d]+.*/i) {
                    $self->cpf_error("Opened file \"$source\" is out of sync with the head. "
                            . "Sync and resolve conflicts, then retry the "
                            . "preflight build");
                }
                $opts->{rt_openedFiles} .= $line . "\n";
            } else {
                next;
            }
    
            # replace all \ with /
            
            $source =~ s/\\/\//g;
            $dest =~ s/\\/\//g;
            # Add all files that are not deletes to the putFiles operation.
            $numFiles ++;
            if ($type ne "D") {
                $self->cpf_addDelta($opts,$source, $dest);
            } else {
                $self->cpf_addDelete($dest);
            }
            
        }
    }

    # create file called externalsRevs if %externalsRevs is non-empty
    if (keys %externalsRevs >= 1) {
        my $str = "";
        while ( my ($key, $value) = each(%externalsRevs) ) {
                $str .= "$value $key\n";
        }
        
        my $rName = File::Spec->catfile($opts->{opt_LogDir}, "externalsRev");
        $self->pf_saveDataToFile($rName, $str);
        my $uFile = File::Spec->catfile("ecpreflight_data", "externalsRev");
        # replace all \ with /
        $rName =~ s/\\/\//g;
        $uFile =~ s/\\/\//g;
        $self->cpf_debug("Adding file \"$rName\" to copy to \"$uFile\" ");
        $opts->{rt_FilesToUpload}{$rName} = $uFile;        
    }

    $self->cpf_closeManifestFiles($opts);
    $self->cpf_uploadFiles($opts);

    # If there aren't any modifications, warn the user, and turn off auto-
    # commit if it was turned on.
    if ($numFiles == 0 && ! $opts->{scm_ExternalsPropertyChanged}) {
        my $warning = "No files are currently open and property svn:externals has not changed";
        if ($opts->{scm_autoCommit}) {
            $warning .= ".  Auto-commit has been turned off for this build";
            $opts->{scm_autoCommit} = 0;
        }
        $self->issueWarningMsg($warning);
    }
}

#------------------------------------------------------------------------------
# handleExternals
#
#       Determine whether svn:externals properties have been added,
#       modified or deleted for directories in the workspace and create 
#       files to preserve this information so svn:externals properties can be 
#       properly replicated in the agent workspace.
#------------------------------------------------------------------------------
sub cpf_handleExternals()
{
    my ($self,$opts) = @_;
    $self->cpf_display("Checking for svn:externals properties");

    my $startDir = File::Spec->curdir();
    if (!File::Spec->file_name_is_absolute($startDir)) {
        $startDir = File::Spec->rel2abs($startDir);
    }

    # Do "svn propget -R svn:externals".  If output is empty, there are no externals here    
    $opts->{scm_ExternalsPropertyOutput} = $self->cpf_svn($opts,"propget -R svn:externals");

    if ($opts->{scm_ExternalsPropertyOutput} eq "") {
        $self->cpf_display("Property svn:externals not defined in this workspace.");
        return;
    }

    # Do "svn diff" and look for any of the following:
    # 1) Added: svn:externals
    # 2) Modified: svn:externals
    # 3) Deleted: svn:externals 
    # For each directory with an add/modify/delete of property svn:externals, create a file
    # listing what svn:externals should exist for the directory.  In the diff output, 
    # for adds/modifies, look for the next line starting with a +, add this line to the 
    # file and all lines after until a blank line is encountered.  For delete, create an empty file.
    # In the agent workspace, to update a directory with a change to property svn:externals,
    # do  "svn propset svn:externals -F <file> <dir with prop change>

    # Don't use svn subroutine since it appends the path to the command to get 
    # absolute paths when we need relative paths here.
    $opts->{scm_DiffOutput} = $self->RunCommand("${\($self->getSVNCommand())} diff");

    if ($opts->{scm_DiffOutput} eq "") {
        $self->cpf_display("Property svn:externals has not changed in this workspace.");
        return;
    }

    # if we get here, we know there have been changes to property svn:externals
    $opts->{scm_ExternalsPropertyChanged} = 1;

    my @diffLines = split(/\n/, $opts->{scm_DiffOutput});

    my $size = $#diffLines + 1;
    my @dirsWithChangedExternals = ();

    for (my $counter = 0; $counter < $size; $counter++) {
        my $line = $diffLines[$counter];
        my $addOrModify = 0;
        my $extDir = "";
        my $pos = 0;
        my $nextLine = "";
        my @contents = ();

        if ($line =~ m/^Added: svn:externals/ || $line =~ m/^Modified: svn:externals/) {
            $addOrModify = 1;
        } elsif ($line =~ m/^Deleted: svn:externals/) {
            $addOrModify = 0;
        } else {
            next;
        }
 
        # Get the directory associated with this svn:external definition
        # by grabbing the line 2 lines up.  Make sure we don't go out of range.
        $pos = $counter - 2;

        if ($pos < 0) {
            next;
        }

        $extDir = $diffLines[$pos];
        
        # strip off the beginning of the line
        $extDir =~ s/^Property changes on: //;
        
        # replace all \ with /
        $extDir =~ s/\\/\//g;

        # remove any leading or trailing spaces
        $extDir =~ s/(^\s+|\s+$)//g;
                      
        $self->cpf_display("Determing status of property svn:externals on directory: $extDir");
        
        push @dirsWithChangedExternals, $extDir;
    
        if ($addOrModify eq "0") {
            $self->cpf_debug("Finished processing deleted property svn:externals on directory: $extDir");
        } else {
            $self->cpf_debug("Gathering details for added or modified property svn:externals on directory: $extDir");
            # Search beyond line at $counter for first line with a + to get first target
            # for this external
            $pos = $counter + 1;
            while ($pos < $size) {
                $nextLine = $diffLines[$pos];
                if ($nextLine =~ m/^\s+\+/) {
                    $nextLine =~ s/^\s+\+//;
                    
                    # replace all \ with /
                    $nextLine =~ s/\\/\//g;
                    
                    # remove any leading or trailing spaces
                    $nextLine =~ s/(^\s+|\s+$)//g;
                
                    $self->cpf_debug("  target: $nextLine");
                    push @contents, $nextLine;
                    last;
                }
                $pos++;
            }
        
            if ($#contents eq "-1") {
                warn("Didn't find any targets for $extDir");
                next;
            }
        
            # Get the rest of the targets for this svn:externals property, if any.
            $pos = $pos + 1;
            while ($pos < $size) {
                $nextLine = $diffLines[$pos];
                if (length($nextLine) < 1) {
                    $self->cpf_debug("Finished processing added or modified property svn:externals for $extDir");
                    $pos++;
                    last;
                }

                # replace all \ with /
                $nextLine =~ s/\\/\//g;
            
                # remove any leading or trailing spaces
                $nextLine =~ s/(^\s+|\s+$)//g;
            
                $self->cpf_debug("  target: $nextLine");
                push @contents, $nextLine;
                $pos++;
            }
            $counter = $pos;
        }
                      
        my $contentsString = "";
        foreach my $c(@contents) {
            $contentsString .= $c . "\n";
        }
        
        my $fName = File::Spec->catfile($opts->{opt_LogDir}, "$#dirsWithChangedExternals");
        $self->pf_saveDataToFile($fName, $contentsString);
        my $uploadFile = File::Spec->catfile("ecpreflight_data", "$#dirsWithChangedExternals");
        # replace all \ with /
        $fName =~ s/\\/\//g;
        $uploadFile =~ s/\\/\//g;
        $self->cpf_debug("Adding file \"$fName\" to copy to \"$uploadFile\" ");
        $opts->{rt_FilesToUpload}{$fName} = $uploadFile;
    }
        
    # create file called externalsProperty if @dirsWithChangedExternals is non-empty
    if ($#dirsWithChangedExternals < 0) {
        $self->cpf_display("No svn:externals properties have been changed in this workspace.");
        return;
    }

    my $str = "";
    foreach my $d (@dirsWithChangedExternals) {
        $str .= $d . "\n";
    }
                    
    my $eName = File::Spec->catfile($opts->{opt_LogDir}, "externalsProperty");
    $self->pf_saveDataToFile($eName, $str);
    my $uFile = File::Spec->catfile("ecpreflight_data", "externalsProperty");
    # replace all \ with /
    $eName =~ s/\\/\//g;
    $uFile =~ s/\\/\//g;
    $self->cpf_debug("Adding file \"$eName\" to copy to \"$uFile\" ");
    $opts->{rt_FilesToUpload}{$eName} = $uFile;
}

#------------------------------------------------------------------------------
# autoCommit
#
#       Automatically commit changes in the user's client.  Error out if:
#       - A check-in has occurred since the preflight was started, and the
#         policy is set to die on any check-in.
#       - A check-in has occurred and opened files are out of sync with the
#         head of the branch.
#       - A check-in has occurred and non-opened files are out of sync with
#         the head of the branch, and the policy is set to die on any changes
#         within the client workspace.
#------------------------------------------------------------------------------
sub cpf_autoCommit()
{
    my ($self,$opts) = @_;
    my $openedFiles = "";

    my @svnPaths = split(/\|/, $opts->{scm_multiple_path});
    foreach my $path (@svnPaths) {
        $opts->{scm_path} = $path;

        # Make sure none of the files have been touched since the build started.
    
        $self->cpf_checkTimestamps($opts);
    
        # Find the latest revision number and compare it to the previously stored
        # revision number.  If they are the same, then proceed.  Otherwise, do some
        # more advanced checks for conflicts.
    
        my $out = $self->cpf_svn($opts,"info");
        $out =~ m/Last Changed Rev: ([\d]+)/;
        my $latestChange = $1;
        $self->cpf_debug("Latest revision: $latestChange");
    
        # If there are any updates that overlap with the opened files, then
        # always error out.
    
        my $path = $opts->{scm_path};
        $path =~ s/\\/\\\\/g;
        if ($self->isWindows()){
            $path =~ s/\//\\\\/g;
        }
        my $status = $self->cpf_svn($opts,"status " .$opts->{scm_ignoreexternals} ." --show-updates --verbose");
        
        foreach my $line(split(/\n/, $status)) {
            if ($line =~ m/^(.).*$path[\/|\\](.*)/ || ($self->isWindows() && $line =~ m/^(.).*$path[\/|\\](.*)/i)) {
    
                if ($line =~ m/^Performing status on external item at /) {
                    next;
                }
    
                my $type = $1;
                if ($type eq " " || $type eq "?" || $type eq "X") {
                    next;
                }
                my $source = $2;
                if (-d File::Spec->catfile($opts->{scm_path}, $source)) {
                    next;
                }
                if ($type eq "C") {
                    $self->cpf_error("Opened file \"$source\" has unresolved conflicts. "
                            . "Resolve conflicts, then retry the preflight build");
                }
                if ($line =~ m/$type[ ]+\*[ ]+[\d]+.*/) {
                    $self->cpf_error("Opened file \"$source\" is out of sync with the "
                            . "head.  Sync and resolve conflicts, then retry "
                            . "the preflight build");
                }
                $openedFiles .= $line . "\n";
            } else {
                next;
            }
        }
    
        # if property svn:externals had been changed before the preflight,
        # make sure no addtional changes have been made
        if ($opts->{scm_ExternalsPropertyChanged}) {
    
            $self->cpf_display("checking svn:externals for auto commit");
    
            chdir($opts->{scm_path});
            my $check = "";
            $check = $self->cpf_svn($opts,"propget -R svn:externals");
    
            if ($check ne $opts->{scm_ExternalsPropertyOutput}) {
                $self->cpf_error("Property svn:externals has changed since the "
                      . " preflight build was launched.");
            }
    
            $check = "";
            $check = $self->RunCommand("${\($self->getSVNCommand())} diff");
            if ($check ne $opts->{scm_DiffOutput}) {
                $self->cpf_error("Changes have been made since the "
                      . " preflight build was launched.");
            }
    
            # for now
            $self->cpf_display("svn:externals changes ok for autocommit");
        }
    }
    # If any file have been added or removed, error out.
    if ($openedFiles ne $opts->{rt_openedFiles}) {
        $self->cpf_error("Files have been added and/or removed from the selected "
                . "changelists since the preflight build was launched");
    } else {
        foreach my $path (@svnPaths) {
            $opts->{scm_path} = "";
            # Commit the changes.
        
            $self->cpf_display("Committing changes from $path");
            $self->cpf_svn($opts,"commit $path -m \"" . $opts->{scm_commitComment}."\"", {LogCommand => 1, LogResult => 1});
            $self->cpf_display("Changes have been successfully submitted");
        }
    }
}

#------------------------------------------------------------------------------
# driver
#
#       Main program for the application.
#------------------------------------------------------------------------------
sub cpf_driver
{
    my ($self,$opts) = @_;
    $self->cpf_display("Executing Subversion actions for ecpreflight");
    #array to store several paths from the command line
    my @multiplePaths = ();
    $::gHelpMessage .= "
Subversion Options:
  --svnpath <path>          The path to the locally accessible source directory
                            in which changes have been made.  This is generally
                            the path to the root of the workspace.
  --svnchangelist           Name of svn changelist to be used during preflight.
  --svnupdatetohead         Use this option to have the agent workspace created
                            during preflight be updated to HEAD.  By default,
                            the agent workspace is updated to the revision 
                            found in the client workspace. NOTE: there is not argument to this option.
  --svnignoreexternals      Causes the preflight process to ignore svn
                            externals. NOTE: there is not argument to this option.
  --svnuser                 Your svn user name.
  --svnpassword             Your svn user's password.
";

    my %ScmOptions = ( 
        "svnpath=s"             => \@multiplePaths,
        "svnuser=s"             => \$opts->{svnUserName},
        "svnpassword=s"         => \$opts->{svnPassword},
        "svnupdatetohead"       => \$opts->{scm_updatetohead},
        "svnchangelist=s"       => \$opts->{svn_changelist},
        "svnignoreexternals"    => \$opts->{scm_ignoreexternals},
    );

    Getopt::Long::Configure("default");
    if (!GetOptions(%ScmOptions)) {
        error($::gHelpMessage);
    }
    
    
    if ($::gHelp eq "1") {
        $self->cpf_display($::gHelpMessage);
        return;
    }
    
    if(@multiplePaths){
        $opts->{scm_path} = join("|",@multiplePaths);
    }
    
    $self->extractOption($opts,"scm_path", { required => 1, cltOption => "svnpath" });
    $self->extractOption($opts,"scm_updatetohead", { required => 0, env => "SVNUPDATETOHEAD" });
    $self->extractOption($opts,"scm_ignoreexternals", { required => 0, env => "SVNIGNOREEXTERNALS" });
    
    # If the preflight is set to auto-commit, require a commit comment.
    if ($opts->{scm_autoCommit} &&
            (!defined($opts->{scm_commitComment})|| $opts->{scm_commitComment} eq "")) {
        $self->cpf_error("Required element \"scm/commitComment\" is empty or absent in "
                . "the provided options.  May also be passed on the command "
                . "line using --commitComment");
    }
    
    $opts->{scm_multiple_path} = $opts->{scm_path};
    my @svnPaths = split(/\|/, $opts->{scm_multiple_path});
    foreach my $path (@svnPaths) {
        $opts->{scm_path} = $path;
        
        # Store the latest checked-in changelist number.
        my $out = $self->cpf_svn($opts,"info");
        my @lines = split(/\n/, $out);
        
        foreach my $line (@lines) {
            if ($line =~ m/Last Changed Rev: ([\d]+)/) {
                $opts->{scm_multiple_lastchange} .= $1 . "|";
            } elsif ($line =~ m/^Revision: ([\d]+)/) {
                # Add "|" to seperate revison from different paths.
                $opts->{scm_lastchange} .= $1 . "|";
            } elsif ($line =~ m/^URL: (.*)/) {
                my $temp = $1;
                #remove espace characters
                $temp =~ s/%20/ /g;
                $opts->{scm_url} .= $temp . "|";
            }
        }
    }
    
    $self->cpf_debug("Extracted path: ".$opts->{scm_multiple_path});
    $self->cpf_debug("Latest revision: ".$opts->{scm_multiple_lastchange});
    $self->cpf_debug("URL: ".$opts->{scm_url});

    if ($opts->{scm_updatetohead}) {
        $self->cpf_display("Agent workspace will be updated to head");
    } else {
        $opts->{scm_updatetohead} = 0;
        $self->cpf_display("Agent workspace will be updated to the same revision as the client: "
            . $opts->{scm_lastchange});
    }

    if ($opts->{scm_ignoreexternals}) {
        $opts->{scm_ignoreexternals} = "--ignore-externals";
        $self->cpf_display("svn externals will be ignored");
    } else {
        $opts->{scm_ignoreexternals} = "";
        $self->cpf_handleExternals($opts);
    }

    # Copy the deltas to a specific location.
    
    $self->cpf_copyDeltas($opts);
    
    # Auto commit if the user has chosen to do so.

    if ($opts->{scm_autoCommit}) {
        if (!$opts->{opt_Testing}) {
            $self->cpf_waitForJob($opts);
        }
        $self->cpf_autoCommit($opts);
    }
}


########################################################################
# registerReports - creates a link for registering the generated report
# in the job step detail
#
# Arguments:
#   -none
#
# Returns:
#   -nothing
#
########################################################################
sub registerReports {
    my $self = shift;
    my $fileName = shift;
    my $ec = $self->getCmdr();

    if($fileName ne ''){
        $ec->abortOnError(0);
        $ec->setProperty("/myJob/artifactsDirectory", '');   
        $ec->setProperty("/myJob/report-urls/@PLUGIN_KEY@ Report","jobSteps/$[jobStepId]/$fileName");
    }
}

####################################################################
# createLinkToChangelogReport
#
# Side Effects:
#   If /myJob/ecscm_changelogs exists, create a report-urls link
#
# Arguments:
#   self -              the object reference
#   reportName -        the name of the report
#
# Returns:
#   Nothing.
####################################################################
sub createLinkToChangelogReport {
    my ($self, $reportName) = @_;

    my $name = $self->getCfg()->getSCMPluginName();

    my ($success, $xpath, $msg) = $self->InvokeCommander({SuppressLog=>1,IgnoreError=>1}, "getProperty", "/plugins/$name/pluginName");
    if (!$success) {
	   print "Error getting promoted plugin name for $name: $msg\n";
	   return;
    }

    my $root = $xpath->findvalue('//value')->string_value;

    ($success, $xpath, $msg) = $self->InvokeCommander({SuppressLog=>1,IgnoreError=>1}, "getProperty", "/myJob/jobId");
    if (!$success) {
	   print "Error getting jobId: $msg\n";
	   return;
    }

    my $id = $xpath->findvalue('//value')->string_value;

    my $prop = "/myJob/report-urls/$reportName";
    my $target = "/commander/pages/$root/reports?jobId=$id";

    # e.g. /commander/pages/EC-DefectTracking-JIRA-1.0/reports?debug=1?jobId=510
    print "Creating link $target\n";
  	
	($success, $xpath, $msg) = $self->InvokeCommander({SuppressLog=>1,IgnoreError=>1}, "setProperty", $prop, $target);

    if (!$success) {
	   print "Error trying to set property $prop: $msg\n";
    }
}

sub getSVNCommand {
    my ($self) = @_;

    my $command = $self->{_svn_command};
    if(!length($command)) {
        $command = "svn";
    }
    
    return $command;
}

sub setSVNCommand {
    my ($self, $svnCommand) = @_;
    $self->{_svn_command} = $svnCommand;
}

1;
