@files = (
    ['//property[propertyName="ECSCM::SVN::Cfg"]/value', 'SVNCfg.pm'], 
    ['//property[propertyName="ECSCM::SVN::Driver"]/value', 'SVNDriver.pm'], 
    ['//property[propertyName="preflight"]/value', 'svnPreflightForm.xml'], 
	['//property[propertyName="checkout"]/value', 'svnCheckoutForm.xml'],
    ['//property[propertyName="sentry"]/value', 'svnSentryForm.xml'], 
    ['//property[propertyName="trigger"]/value', 'svnTriggerForm.xml'], 
    ['//property[propertyName="createConfig"]/value', 'svnCreateConfigForm.xml'], 
    ['//property[propertyName="editConfig"]/value', 'svnEditConfigForm.xml'], 
    ['//property[propertyName="ec_setup"]/value', 'ec_setup.pl'],
    ['//procedure[procedureName="CommitChanges"]/propertySheet/property[propertyName="ec_parameterForm"]/value', 'svnCommitForm.xml'],	
    ['//procedure[procedureName="Update"]/propertySheet/property[propertyName="ec_parameterForm"]/value', 'svnUpdateForm.xml'],	
    ['//procedure[procedureName="Preflight"]/propertySheet/property[propertyName="ec_parameterForm"]/value', 'svnPreflightForm.xml'],
);