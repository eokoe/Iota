
package Iota::Schema::ResultSet::RegionVariableValue;

use namespace::autoclean;

use Moose;
extends 'DBIx::Class::ResultSet';
with 'Iota::Role::Verification';
with 'Iota::Schema::Role::InflateAsHashRef';

use Data::Verifier;
use JSON qw /encode_json/;
use String::Random;
use MooseX::Types::Email qw/EmailAddress/;

use Iota::IndicatorData;

use Iota::Types qw /VariableType DataStr/;

sub _build_verifier_scope_name { 'region.variable.value' }
use DateTimeX::Easy;

my $str2number = sub {
    my $str = shift;
    if ( $str =~ /[^\d]/ ) {
        $str =~ s/\.(\d{3})/$1/g;
        $str =~ s/\s(\d{3})/$1/g;
        $str =~ s/\,/./;
    }
    return $str;
};

sub value_check {
    my ( $self, $r ) = @_;

    my $variable_id = $r->get_value('variable_id');
    my $schema      = $self->result_source->schema;
    unless ($variable_id) {
        $variable_id = $self->search( { id => $r->get_value('id') } )->first->variable_id;
    }

    my $var = $schema->resultset('Variable')->find( { id => $variable_id } );

    if ( $var->type eq 'int' && $r->get_value('value') !~ /^[-+]?[0-9]+$/ ) {
        return 0;
    }
    elsif ( $var->type eq 'num' && $r->get_value('value') !~ /^[-+]?[0-9]+\.?[0-9]*$/ ) {
        return 0;
    }

    return 1;
}

# TODO deixar o campo 'source' obrigatorio quando o campo 'value' for vazio
sub verifiers_specs {
    my $self = shift;
    return {
        create => Data::Verifier->new(
            filters => [qw(trim)],
            profile => {

                value => {
                    required   => 0,
                    type       => 'Str',
                    post_check => sub {
                        my $r = shift;
                        return $self->value_check($r);
                    },
                    filters => [$str2number]
                },
                source        => { required => 0, type => 'Str' },
                observations  => { required => 0, type => 'Str' },
                user_id       => { required => 1, type => 'Int' },
                region_id     => { required => 1, type => 'Int' },
                value_of_date => {
                    required   => 1,
                    type       => DataStr,
                    post_check => sub {
                        my $r = shift;

                        #return 0 if (!$r->get_value('value'));  # TODO verificar se foi salvo justificativa

                        my $schema = $self->result_source->schema;
                        my $var    = $schema->resultset('Variable')->find( { id => $r->get_value('variable_id') } );
                        my $date   = DateTimeX::Easy->new( $r->get_value('value_of_date') )->datetime;

                        # f_extract_period_edge
                        return $self->search(
                            {
                                user_id     => $r->get_value('user_id'),
                                variable_id => $r->get_value('variable_id'),
                                valid_from  => $schema->f_extract_period_edge( $var ? $var->period : 'yearly', $date )
                                  ->{period_begin}
                            }
                        )->count == 0;
                      }

                },
                variable_id => {
                    required   => 1,
                    type       => 'Int',
                    post_check => sub {
                        my $r = shift;
                        return $self->result_source->schema->resultset('Variable')
                          ->find( { id => $r->get_value('variable_id') } ) ? 1 : 0;
                      }
                },
            },
        ),

        update => Data::Verifier->new(
            filters => [qw(trim)],
            profile => {

                source => { required => 0, type => 'Str' },
                id     => {
                    required   => 1,
                    type       => 'Int',
                    post_check => sub {
                        my $r = shift;
                        return $self->search( { id => $r->get_value('id') } )->count == 1;
                      }

                },
                observations => { required => 0, type => 'Str' },
                value        => {
                    required   => 0,
                    type       => 'Str',
                    post_check => sub {
                        my $r = shift;
                        return $self->value_check($r);
                    },
                    filters => [$str2number]
                },
                value_of_date => {
                    required   => 1,
                    type       => DataStr,
                    post_check => sub {
                        my $r = shift;

                        #return 0 if (!$r->get_value('value')); # TODO verificar se foi salvo justificativa

                        my $schema = $self->result_source->schema;
                        my $var = $self->search( { id => $r->get_value('id') } )->first;

                        my $date = DateTimeX::Easy->new( $r->get_value('value_of_date') )->datetime;

                        # f_extract_period_edge
                        return $var && $self->search(
                            {
                                id => $r->get_value('id'),
                                valid_from =>
                                  $schema->f_extract_period_edge( $var->variable->period, $date )->{period_begin}
                            }
                        )->count == 1;
                      }

                },
            },
        ),

        put => Data::Verifier->new(
            filters => [qw(trim)],
            profile => {

                source  => { required => 0, type => 'Str' },
                file_id => { required => 0, type => 'Int' },

                region_id => { required => 1, type => 'Int' },

                value => {
                    required   => 0,
                    type       => 'Str',
                    post_check => sub {
                        my $r = shift;

                        return $self->value_check($r);
                    },
                    filters => [$str2number]
                },
                observations  => { required => 0, type => 'Str' },
                user_id       => { required => 1, type => 'Int' },
                value_of_date => {
                    required => 1,
                    type     => DataStr,

                    #post_check => sub {
                    #    my $r = shift;
                    #    return 0 if (!$r->get_value('justification_of_missing_field') && !$r->get_value('value'));
                    #    return 1;
                    #},

                },
                variable_id => {
                    required   => 1,
                    type       => 'Int',
                    post_check => sub {
                        my $r = shift;
                        return $self->result_source->schema->resultset('Variable')
                          ->find( { id => $r->get_value('variable_id') } ) ? 1 : 0;
                      }
                },
            },
        ),

    };
}

sub action_specs {
    my $self = shift;
    return {
        create => sub {
            my %values = shift->valid_values;
            $values{value_of_date} = DateTimeX::Easy->new( $values{value_of_date} )->datetime;

            my $schema = $self->result_source->schema;
            my $var    = $schema->resultset('Variable')->find( { id => $values{variable_id} } );
            my $date   = $values{value_of_date};

            my $dates = $schema->f_extract_period_edge( $var->period || 'yearly', $date );
            $values{valid_from}  = $dates->{period_begin};
            $values{valid_until} = $dates->{period_end};

            my $varvalue = $self->create( \%values );
            $varvalue->discard_changes;

            my $data = Iota::IndicatorData->new( schema => $self->result_source->schema );

            if ( exists $values{source} && $values{source} ) {
                my $source =
                  $self->result_source->schema->resultset('Source')->find_or_new( { name => $values{source} } );
                if ( !$source->in_storage ) {
                    $source->user_id( $values{user_id} );
                    $source->insert;
                }
            }
            $data->upsert(
                indicators => [ $data->indicators_from_variables( variables => [ $varvalue->id ] ) ],
                dates      => [ $values{valid_from} ],
                user_id    => $varvalue->user_id,
                regions_id => [ $varvalue->region_id ]
            );

            return $varvalue;
        },
        update => sub {
            my %values = shift->valid_values;
            $values{value_of_date} = DateTimeX::Easy->new( $values{value_of_date} )->datetime;

            do { delete $values{$_} unless defined $values{$_} }
              for keys %values;
            return unless keys %values;

            $values{observations} ||= undef;
            $values{source}       ||= undef;

            my $var = $self->find( delete $values{id} )->update( \%values );
            $var->discard_changes;

            my $data = Iota::IndicatorData->new( schema => $self->result_source->schema );

            if ( exists $values{source} && $values{source} ) {
                my $source =
                  $self->result_source->schema->resultset('Source')->find_or_new( { name => $values{source} } );
                if ( !$source->in_storage ) {
                    $source->user_id( $values{user_id} );
                    $source->insert;
                }
            }

            $data->upsert(
                indicators => [ $data->indicators_from_variables( variables => [ $var->id ] ) ],
                dates      => [ $values{valid_from} ],
                user_id    => $var->user_id,
                regions_id => [ $var->region_id ],
            );

            return $var;
        },
        put => sub {
            my %values = shift->valid_values;

            my $schema = $self->result_source->schema;
            my $var    = $schema->resultset('Variable')->find( $values{variable_id} );

            $self->_put( $var ? $var->period : 'yearly', %values );

        },

    };
}

sub _put {
    my ( $self, $period, %values ) = @_;
    $values{value_of_date} = DateTimeX::Easy->new( $values{value_of_date} )->datetime;

    my $schema = $self->result_source->schema;

    do { delete $values{$_} unless defined $values{$_} }
      for keys %values;
    return unless keys %values;

    my $dates = $schema->f_extract_period_edge( $period, $values{value_of_date} );

    # confere se a regiao eh mesmo da cidade desse usuario
    my $region = $schema->resultset('Region')->find( $values{region_id} );
    my $user   = $schema->resultset('User')->find( $values{user_id} );

    if ( $user->city_id && $region->city_id != $user->city_id ) {
        die 'Illegal region for user.';
    }

    # procura por uma variavel daquele usuario naquele periodo, se
    # existir, atualiza a data e o valor!
    my $row = $self->search(
        {
            user_id     => $values{user_id},
            region_id   => $values{region_id},
            variable_id => $values{variable_id},
            valid_from  => $dates->{period_begin}
        }
    )->next;

    if ($row) {
        $row->update(
            {
                value         => $values{value},
                value_of_date => $values{value_of_date},

                ( exists $values{source} ? ( source => $values{source} ) : () ),

                ( exists $values{observations} ? ( observations => $values{observations} ) : () ),

                ( exists $values{file_id} ? ( file_id => $values{file_id} ) : () ),

            }
        );
        $row->discard_changes;
    }
    else {

        $values{valid_from}  = $dates->{period_begin};
        $values{valid_until} = $dates->{period_end};

        $row = $self->create( \%values );
    }

    if ( exists $values{source} && $values{source} ) {
        my $source = $self->result_source->schema->resultset('Source')->find_or_new( { name => $values{source} } );
        if ( !$source->in_storage ) {
            $source->user_id( $values{user_id} );
            $source->insert;
        }
    }

    my $data = Iota::IndicatorData->new( schema => $self->result_source->schema );

    $data->upsert(
        indicators => [ $data->indicators_from_variables( variables => [ $values{variable_id} ] ) ],
        dates      => [ $dates->{period_begin} ],
        user_id    => $row->user_id,
        regions_id => [ $row->region_id ]
    );

    return $row;
}

1;
