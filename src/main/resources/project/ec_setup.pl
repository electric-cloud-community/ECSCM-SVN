my $projPrincipal = "project: $pluginName";
my $ecscmProj     = '$[/plugins/ECSCM/project]';

if ( $promoteAction eq 'promote' ) {

    # Register our SCM type with ECSCM
    $batch->setProperty( "/plugins/ECSCM/project/scm_types/@PLUGIN_KEY@",
        "Subversion" );

    # Give our project principal execute access to the ECSCM project
    my $xpath = $commander->getAclEntry( "user", $projPrincipal,
        { projectName => $ecscmProj } );
    if ( $xpath->findvalue('//code') eq 'NoSuchAclEntry' ) {
        $batch->createAclEntry(
            "user",
            $projPrincipal,
            {   projectName      => $ecscmProj,
                executePrivilege => "allow"
            }
        );
    }
}
elsif ( $promoteAction eq 'demote' ) {

    # unregister with ECSCM
    $batch->deleteProperty("/plugins/ECSCM/project/scm_types/@PLUGIN_KEY@");

    # remove permissions
    my $xpath = $commander->getAclEntry( "user", $projPrincipal,
        { projectName => $ecscmProj } );
    if ( $xpath->findvalue('//principalName') eq $projPrincipal ) {
        $batch->deleteAclEntry( "user", $projPrincipal,
            { projectName => $ecscmProj } );
    }
    $batch->deleteProperty(
        "/server/ec_customEditors/pickerStep/@PLUGIN_KEY@ - Checkout");
}

# Unregister current and past entries first.
$batch->deleteProperty("/server/ec_customEditors/pickerStep/ECSCM-SVN - Checkout");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/ECSCM-SVN - CommitChanges");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/ECSCM-SVN - Preflight");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/SVN - Checkout");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/SVN - CommitChanges");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/SVN - Commit Changes");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/SVN - Preflight");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/SVN - Update");

my %checkout = (
    label       => "SVN - Checkout",
    procedure   => "CheckoutCode",
    description => "Checkout code from SVN.",
    category    => "Source Code Management"
);
my %commit = (
    label       => "SVN - Commit Changes",
    procedure   => "CommitChanges",
    description => "Commit pending changes to a SVN server.",
    category    => "Source Code Management"
);
my %Preflight = (
    label       => "SVN - Preflight",
    procedure   => "Preflight",
    description => "Checkout code from SVN during Preflight",
    category    => "Source Code Management"
);
my %Update = (
    label       => "SVN - Update",
    procedure   => "Update",
    description => "Brings changes from the repository into your working copy.",
    category    => "Source Code Management"
);

@::createStepPickerSteps = ( \%checkout, \%commit, \%Preflight, \%Update );

