####################################################################
#
# ECSCM::SVN::Cfg: Object definition of a SVN SCM configuration.
#
####################################################################
package ECSCM::SVN::Cfg;
@ISA = (ECSCM::Base::Cfg);
if (!defined ECSCM::Base::Cfg) {
    require ECSCM::Base::Cfg;
}

####################################################################
# Object constructor for ECSCM::Base::Cfg
#
# Inputs
#   cmdr  = a previously initialized ElectricCommander handle
#   name  = a name for this configuration
####################################################################
sub new {
    my $class = shift;

    my $cmdr = shift;
    my $name = shift;

    my($self) = ECSCM::Base::Cfg->new($cmdr,"$name");
    bless ($self, $class);
    return $self;
}


1;
