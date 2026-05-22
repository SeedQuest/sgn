package SGN::Controller::SeedQuest::Solvi;

use Moose;
use namespace::autoclean;
use JSON qw(encode_json);
use URI::FromHash 'uri';
use CXGN::Phenotypes::StorePhenotypes;
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

    my ($parsed, $filename, $parse_error) = $self->_parse_upload($c);
    if ($parse_error) {
        $self->_json_response($c, { error => $parse_error });
    }

    my $schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');
    my $summary = $self->_preview_summary($schema, $parsed, $filename);
    $self->_json_response($c, $summary);
}

sub verify_write : Path('/ajax/seedquest/solvi/verify') Args(0) {
    my ($self, $c) = @_;

    unless ($self->_has_real_user($c)) {
        $self->_json_response($c, { error => 'You must be logged in first!' });
    }

    unless ($self->_can_verify_write($c)) {
        $self->_json_response($c, { error => 'Solvi write verification requires submitter or curator privileges.' });
    }

    my ($parsed, $filename, $parse_error) = $self->_parse_upload($c);
    if ($parse_error) {
        $self->_json_response($c, { error => $parse_error });
    }

    my $schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');
    my $metadata_schema = $c->dbic_schema('CXGN::Metadata::Schema');
    my $phenome_schema = $c->dbic_schema('CXGN::Phenome::Schema');
    my $user = $c->user();
    my $person = $user->get_object();
    my $user_id = $person->get_sp_person_id();
    my $operator = eval { $person->get_username() } || eval { $user->get_username() } || 'unknown';
    my $timestamp = $self->_metadata_timestamp();
    my %metadata = (
        archived_file => $filename,
        archived_file_type => 'seedquest solvi csv verify-only',
        operator => $operator,
        date => $timestamp,
    );

    $c->tempfiles_subdir('/delete_nd_experiment_ids');
    my $temp_file_nd_experiment_id = $c->config->{basepath} . '/' . $c->tempfile(
        TEMPLATE => 'delete_nd_experiment_ids/fileXXXX'
    );

    my $store_phenotypes = CXGN::Phenotypes::StorePhenotypes->new(
        basepath => $c->config->{basepath},
        dbhost => $c->config->{dbhost},
        dbname => $c->config->{dbname},
        dbuser => $c->config->{dbuser},
        dbpass => $c->config->{dbpass},
        temp_file_nd_experiment_id => $temp_file_nd_experiment_id,
        bcs_schema => $schema,
        metadata_schema => $metadata_schema,
        phenome_schema => $phenome_schema,
        user_id => $user_id,
        stock_list => $parsed->{units},
        trait_list => $parsed->{variables},
        values_hash => $parsed->{data},
        has_timestamps => 1,
        overwrite_values => 0,
        remove_values => 0,
        metadata_hash => \%metadata,
        composable_validation_check_name => $c->config->{composable_validation_check_name},
        allow_repeat_measures => $c->config->{allow_repeat_measures},
    );

    my ($verified_warning, $verified_error);
    my $ok = eval {
        ($verified_warning, $verified_error) = $store_phenotypes->verify();
        1;
    };
    if (!$ok) {
        $verified_error = $@ || 'Solvi write verification failed.';
    }
    if ($verified_error) {
        $self->_json_response($c, { error => "Breedbase write verification failed: $verified_error" });
    }

    my $summary = $self->_preview_summary($schema, $parsed, $filename);
    $summary->{verified} = JSON::true;
    $summary->{message} = 'Breedbase write verification passed. No observations were stored.';
    $summary->{warning} = $verified_warning || '';
    $summary->{write_enabled} = JSON::false;
    $self->_json_response($c, $summary);
}

sub _parse_upload {
    my ($self, $c) = @_;

    my $upload = $c->req->upload('solvi_csv_file');
    unless ($upload) {
        return (undef, undef, 'No Solvi CSV file was uploaded.');
    }

    my $filename = $upload->filename || '';
    if ($filename !~ /\.csv\z/i) {
        return (undef, undef, 'Solvi upload expects a .csv file.');
    }

    my $size = eval { $upload->size } || 0;
    if ($size > $MAX_UPLOAD_BYTES) {
        return (undef, undef, 'Solvi CSV is too large. Maximum size is 10 MB.');
    }

    my $trait_map = $c->config->{seedquest_solvi_trait_map} || {};
    my $parsed = SeedQuest::Solvi::Parser->new(trait_map => $trait_map)->parse_file(
        $upload->tempname,
        source_filename => $filename,
    );

    if ($parsed->{error}) {
        return (undef, undef, $parsed->{error});
    }

    return ($parsed, $filename, undef);
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

sub _can_verify_write {
    my ($self, $c) = @_;
    my $user = $c->user();
    return 0 unless $user;
    my $user_type = eval { $user->get_object()->get_user_type() } || '';
    return 1 if $user_type eq 'curator' || $user_type eq 'submitter';
    my @roles = eval { $user->roles() };
    return scalar(grep { $_ eq 'curator' || $_ eq 'submitter' } @roles) ? 1 : 0;
}

sub _metadata_timestamp {
    my ($sec, $min, $hour, $mday, $mon, $year) = localtime();
    return sprintf(
        '%04d-%02d-%02d_%02d:%02d:%02d',
        $year + 1900,
        $mon + 1,
        $mday,
        $hour,
        $min,
        $sec,
    );
}

__PACKAGE__->meta->make_immutable;

1;
