package SGN::Controller::SeedQuest::Solvi;

use Moose;
use namespace::autoclean;
use JSON qw(encode_json);
use URI::FromHash 'uri';
use SeedQuest::Solvi::Parser;
use SGN::Model::Cvterm;

BEGIN { extends 'Catalyst::Controller'; }

my $MAX_UPLOAD_BYTES = 10 * 1024 * 1024;

sub solvi_index : Path('/tools/seedquest/solvi') Args(0) {
    my ($self, $c) = @_;

    if (!$self->_has_real_user($c)) {
        $c->res->redirect(uri(
            path  => '/user/login',
            query => { goto_url => $c->req->uri->path_query },
        ));
        return;
    }

    $c->stash->{template} = '/seedquest/tools/solvi/preview.mas';
}

sub preview : Path('/ajax/seedquest/solvi/preview') Args(0) {
    my ($self, $c) = @_;

    unless ($self->_has_real_user($c)) {
        $self->_json_response($c, { error => 'You must be logged in first!' });
    }

    my $upload = $c->req->upload('solvi_csv_file');
    unless ($upload) {
        $self->_json_response($c, { error => 'No Solvi CSV file was uploaded.' });
    }

    my $filename = $upload->filename || '';
    if ($filename !~ /\.csv\z/i) {
        $self->_json_response($c, { error => 'Solvi preview expects a .csv file.' });
    }

    my $size = eval { $upload->size } || 0;
    if ($size > $MAX_UPLOAD_BYTES) {
        $self->_json_response($c, { error => 'Solvi CSV is too large for preview.' });
    }

    my $trait_map = $c->config->{seedquest_solvi_trait_map} || {};
    my $parsed = SeedQuest::Solvi::Parser->new(trait_map => $trait_map)->parse_file(
        $upload->tempname,
        source_filename => $filename,
    );

    if ($parsed->{error}) {
        $self->_json_response($c, { error => $parsed->{error} });
    }

    my $schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');
    my $summary = $self->_preview_summary($schema, $parsed, $filename);
    $self->_json_response($c, $summary);
}

sub _preview_summary {
    my ($self, $schema, $parsed, $filename) = @_;

    my @trait_status = map { $self->_trait_status($schema, $_) } @{ $parsed->{variables} || [] };
    my @preview_units;
    my $observation_count = 0;

    for my $unit (@{ $parsed->{units} || [] }) {
        my %values;
        for my $trait (@{ $parsed->{variables} || [] }) {
            my $observations = $parsed->{data}{$unit}{$trait} || [];
            $observation_count += scalar(@$observations);
            next unless @$observations;
            $values{$trait} = $observations->[0][0];
        }

        if (@preview_units < 10) {
            push @preview_units, {
                unit => $unit,
                values => \%values,
            };
        }
    }

    return {
        success => JSON::true,
        filename => $filename,
        flight_date => $parsed->{flight_date} || '',
        unit_count => scalar(@{ $parsed->{units} || [] }),
        variable_count => scalar(@{ $parsed->{variables} || [] }),
        observation_count => $observation_count,
        dropped_buffers => $parsed->{dropped_buffers} || 0,
        variables => \@trait_status,
        preview_units => \@preview_units,
        write_enabled => JSON::false,
    };
}

sub _json_response {
    my ($self, $c, $payload) = @_;
    $c->res->content_type('application/json');
    $c->res->body(encode_json($payload));
    $c->detach;
}

sub _trait_status {
    my ($self, $schema, $trait_name) = @_;

    my $cvterm_id;
    my $match_name = '';
    my $row = eval { SGN::Model::Cvterm->get_cvterm_row_from_trait_name($schema, $trait_name) };

    if ($row) {
        my $is_variable = $row->search_related(
            'cvterm_relationship_subjects',
            { 'type.name' => 'VARIABLE_OF' },
            { join => 'type', rows => 1 },
        )->count;
        if ($is_variable) {
            $cvterm_id = $row->cvterm_id;
            $match_name = $trait_name;
        }
    }

    return {
        name => $trait_name,
        cvterm_id => $cvterm_id || '',
        matched_name => $match_name,
        status => $cvterm_id ? 'matched' : 'missing',
    };
}

sub _has_real_user {
    my ($self, $c) = @_;
    my $user = $c->user();
    return 0 unless $user;
    my $person = eval { $user->get_object() };
    return 0 unless $person;
    my $sp_person_id = eval { $person->get_sp_person_id() };
    return defined $sp_person_id && $sp_person_id > 0 ? 1 : 0;
}

__PACKAGE__->meta->make_immutable;

1;
