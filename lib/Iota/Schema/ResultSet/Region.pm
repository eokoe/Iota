
package Iota::Schema::ResultSet::Region;

use namespace::autoclean;

use Moose;
extends 'DBIx::Class::ResultSet';
with 'Iota::Role::Verification';
with 'Iota::Schema::Role::InflateAsHashRef';

use Text2URI;
my $text2uri = Text2URI->new();    # tem lazy la, don't worry

use Data::Verifier;
use Iota::IndicatorFormula;

sub _build_verifier_scope_name { 'city.region' }

sub verifiers_specs {
    my $self = shift;
    return {
        create => Data::Verifier->new(
            filters => [qw(trim)],
            profile => {
                name        => { required => 1, type => 'Str' },
                description => { required => 0, type => 'Str' },
                city_id     => { required => 1, type => 'Int' },
                created_by  => { required => 1, type => 'Int' },

                upper_region => {
                    required   => 0,
                    type       => 'Int',
                    post_check => sub {
                        my $r = shift;
                        my $axis =
                          $self->result_source->schema->resultset('Region')
                          ->find( { id => $r->get_value('upper_region') } );
                        return defined $axis;
                      }
                },

                automatic_fill => { required => 0, type => 'Bool' },

            },
        ),

        update => Data::Verifier->new(
            filters => [qw(trim)],
            profile => {
                id          => { required => 1, type => 'Int' },
                name        => { required => 0, type => 'Str' },
                description => { required => 0, type => 'Str' },

                upper_region => {
                    required   => 0,
                    type       => 'Int',
                    post_check => sub {
                        my $r = shift;
                        my $axis =
                          $self->result_source->schema->resultset('Region')
                          ->find( { id => $r->get_value('upper_region') } );
                        return defined $axis;
                      }
                },

                automatic_fill => { required => 0, type => 'Bool' },

            },
        ),

    };
}

sub action_specs {
    my $self = shift;
    return {
        create => sub {
            my %values = shift->valid_values;

            do { delete $values{$_} unless defined $values{$_} }
              for keys %values;

            $values{name_url} = $text2uri->translate( $values{name} );

            $values{depth_level} = 3 if exists $values{upper_region} && $values{upper_region};

            if ( !exists $values{depth_level} || $values{depth_level} == 2 ) {
                $values{name_url} = 'subprefeitura:' . $values{name_url};
            }

            my $var = $self->create( \%values );
            return $var;
        },
        update => sub {
            my %values = shift->valid_values;
            do { delete $values{$_} unless defined $values{$_} }
              for keys %values;

            $values{name_url} = $text2uri->translate( $values{name} ) if exists $values{name} && $values{name};
            $values{depth_level} = 3 if exists $values{upper_region} && $values{upper_region};

            if (   exists $values{depth_level}
                && exists $values{name}
                && $values{depth_level} == 2 ) {

                $values{name_url} = 'subprefeitura:' . $values{name_url};

            }

            return unless keys %values;

            my $var = $self->find( delete $values{id} );
            $var->update( \%values );

            $var->discard_changes;

            return $var;
        },

    };
}

1;
