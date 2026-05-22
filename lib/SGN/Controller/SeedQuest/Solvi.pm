package SGN::Controller::SeedQuest::Solvi;

use Moose;
use namespace::autoclean;
use Digest::MD5 qw(md5_hex);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Spec;
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

    my ($parsed, $upload_info, $parse_error) = $self->_parse_upload($c);
    if ($parse_error) {
        $self->_json_response($c, { error => $parse_error });
    }

    my $schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');
    my $summary = $self->_preview_summary($schema, $parsed, $upload_info);
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

    my ($parsed, $upload_info, $parse_error) = $self->_parse_upload($c, require_timestamp => 1);
    if ($parse_error) {
        $self->_json_response($c, { error => $parse_error });
    }

    my ($store_context, $store_context_error) = $self->_store_context(
        $c,
        $parsed,
        $upload_info,
        archived_file_type => 'seedquest solvi csv verify-only',
    );
    if ($store_context_error) {
        $self->_json_response($c, { error => $store_context_error });
    }

    my ($verified_warning, $verified_error);
    my $ok = eval {
        ($verified_warning, $verified_error) = $store_context->{store_phenotypes}->verify();
        1;
    };
    if (!$ok) {
        $verified_error = $@ || 'Solvi write verification failed.';
    }
    if ($verified_error) {
        $self->_json_response($c, { error => "Breedbase write verification failed: $verified_error" });
    }

    my $duplicates = $self->_duplicate_report($store_context->{schema}, $parsed, $upload_info);
    my $summary = $self->_preview_summary($store_context->{schema}, $parsed, $upload_info);
    $summary->{verified} = JSON::true;
    $summary->{duplicates} = $duplicates;
    $summary->{message} = 'Breedbase write verification passed. No observations were stored.';
    my @warnings;
    push @warnings, $verified_warning if $verified_warning;
    if (($duplicates->{existing_observation_count} || 0) > 0) {
        push @warnings, 'Existing observations were found for this flight timestamp.';
    }
    if (($duplicates->{file_duplicate_count} || 0) > 0) {
        push @warnings, 'A file with the same checksum already exists in archived phenotype metadata.';
    }
    $summary->{warning} = join(' ', @warnings);
    $summary->{write_enabled} = JSON::false;
    $self->_json_response($c, $summary);
}

sub import_data : Path('/ajax/seedquest/solvi/import') Args(0) {
    my ($self, $c) = @_;

    unless ($self->_has_real_user($c)) {
        $self->_json_response($c, { error => 'You must be logged in first!' });
    }

    unless ($self->_can_verify_write($c)) {
        $self->_json_response($c, { error => 'Solvi import requires submitter or curator privileges.' });
    }

    my ($parsed, $upload_info, $parse_error) = $self->_parse_upload($c, require_timestamp => 1);
    if ($parse_error) {
        $self->_json_response($c, { error => $parse_error });
    }

    my ($check_context, $check_context_error) = $self->_store_context(
        $c,
        $parsed,
        $upload_info,
        archived_file_type => 'seedquest solvi csv import check',
    );
    if ($check_context_error) {
        $self->_json_response($c, { error => $check_context_error });
    }

    my ($verified_warning, $verified_error);
    my $verified_ok = eval {
        ($verified_warning, $verified_error) = $check_context->{store_phenotypes}->verify();
        1;
    };
    if (!$verified_ok) {
        $verified_error = $@ || 'Solvi import verification failed.';
    }
    if ($verified_error) {
        $self->_json_response($c, { error => "Breedbase import verification failed: $verified_error" });
    }

    my $duplicates = $self->_duplicate_report($check_context->{schema}, $parsed, $upload_info);
    my ($can_import, $import_blocker) = $self->_can_import_duplicate_report($duplicates);
    my $summary = $self->_preview_summary($check_context->{schema}, $parsed, $upload_info);
    $summary->{verified} = JSON::true;
    $summary->{duplicates} = $duplicates;
    $summary->{confirmation_required} = JSON::true;
    $summary->{can_import} = $can_import ? JSON::true : JSON::false;
    $summary->{write_enabled} = $can_import ? JSON::true : JSON::false;
    $summary->{message} = $can_import
        ? 'Solvi file is verified and ready for import. Confirm once more to store observations.'
        : 'Solvi import is blocked until duplicate conflicts are resolved.';

    my @warnings;
    push @warnings, $verified_warning if $verified_warning;
    push @warnings, $import_blocker if $import_blocker;
    $summary->{warning} = join(' ', @warnings);

    if (!$can_import || (($c->req->param('confirm_import') || '') ne '1')) {
        $self->_json_response($c, $summary);
    }

    my ($archived_file, $archive_error) = $self->_archive_upload_file($c, $upload_info);
    if ($archive_error) {
        $self->_json_response($c, { error => $archive_error });
    }

    my ($store_context, $store_context_error) = $self->_store_context(
        $c,
        $parsed,
        $upload_info,
        archived_file => $archived_file,
        archived_file_type => 'seedquest solvi csv import',
    );
    if ($store_context_error) {
        $self->_json_response($c, { error => $store_context_error });
    }

    my ($store_warning, $store_error);
    my $prestore_ok = eval {
        ($store_warning, $store_error) = $store_context->{store_phenotypes}->verify();
        1;
    };
    if (!$prestore_ok) {
        $store_error = $@ || 'Solvi import verification failed before storing.';
    }
    if ($store_error) {
        $self->_json_response($c, { error => "Breedbase import verification failed before storing: $store_error" });
    }

    my ($stored_error, $stored_success, $stored_details);
    my $stored_ok = eval {
        ($stored_error, $stored_success, $stored_details) = $store_context->{store_phenotypes}->store();
        1;
    };
    if (!$stored_ok) {
        $stored_error = $@ || 'Solvi import failed.';
    }
    if ($stored_error) {
        $self->_json_response($c, { error => "Solvi import failed: $stored_error" });
    }

    $summary->{confirmation_required} = JSON::false;
    $summary->{can_import} = JSON::false;
    $summary->{write_enabled} = JSON::false;
    $summary->{imported} = JSON::true;
    $summary->{stored_observation_count} = scalar(@{ $stored_details || [] });
    $summary->{archived_file} = $self->_safe_filename($upload_info->{filename});
    $summary->{message} = $stored_success || 'Solvi observations were imported successfully.';
    push @warnings, $store_warning if $store_warning;
    $summary->{warning} = join(' ', grep { $_ } @warnings);
    $self->_json_response($c, $summary);
}

sub _parse_upload {
    my ($self, $c, %opts) = @_;

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

    my $file_md5 = $self->_file_md5($upload->tempname);
    my $trait_map = $c->config->{seedquest_solvi_trait_map} || {};
    my $parsed = SeedQuest::Solvi::Parser->new(trait_map => $trait_map)->parse_file(
        $upload->tempname,
        source_filename => $filename,
    );

    if ($parsed->{error}) {
        return (undef, undef, $parsed->{error});
    }

    my ($flight_timestamp, $flight_timestamp_input, $timestamp_error) = $self->_resolve_flight_timestamp(
        $c->req->param('flight_timestamp'),
        $parsed->{flight_date},
        $opts{require_timestamp},
    );
    if ($timestamp_error) {
        return (undef, undef, $timestamp_error);
    }
    $self->_apply_flight_timestamp($parsed, $flight_timestamp) if $flight_timestamp;

    my $upload_info = {
        filename => $filename,
        tempname => $upload->tempname,
        file_md5 => $file_md5,
        flight_timestamp => $flight_timestamp || '',
        flight_timestamp_input => $flight_timestamp_input || '',
        sensor => $self->_clean_text_param($c, 'sensor'),
        platform => $self->_clean_text_param($c, 'platform'),
        processing_version => $self->_clean_text_param($c, 'processing_version'),
        source_id => $self->_clean_text_param($c, 'source_id'),
    };

    return ($parsed, $upload_info, undef);
}

sub _preview_summary {
    my ($self, $schema, $parsed, $upload_info) = @_;

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
        filename => $upload_info->{filename},
        file_md5 => $upload_info->{file_md5} || '',
        flight_date => $parsed->{flight_date} || '',
        flight_timestamp => $upload_info->{flight_timestamp} || '',
        flight_timestamp_input => $upload_info->{flight_timestamp_input} || '',
        unit_count => scalar(@{ $parsed->{units} || [] }),
        variable_count => scalar(@{ $parsed->{variables} || [] }),
        observation_count => $observation_count,
        dropped_buffers => $parsed->{dropped_buffers} || 0,
        variables => \@trait_status,
        preview_units => \@preview_units,
        write_enabled => JSON::false,
    };
}

sub _store_context {
    my ($self, $c, $parsed, $upload_info, %opts) = @_;

    my $schema = $c->dbic_schema('Bio::Chado::Schema', 'sgn_chado');
    my $metadata_schema = $c->dbic_schema('CXGN::Metadata::Schema');
    my $phenome_schema = $c->dbic_schema('CXGN::Phenome::Schema');
    my $user = $c->user();
    my $person = $user->get_object();
    my $user_id = $person->get_sp_person_id();
    my $operator = eval { $person->get_username() } || eval { $user->get_username() } || 'unknown';
    my $timestamp = $self->_metadata_timestamp();
    my %metadata = (
        archived_file => exists $opts{archived_file} ? $opts{archived_file} : $upload_info->{filename},
        archived_file_type => $opts{archived_file_type} || 'seedquest solvi csv',
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

    return ({
        schema => $schema,
        metadata_schema => $metadata_schema,
        phenome_schema => $phenome_schema,
        store_phenotypes => $store_phenotypes,
        metadata => \%metadata,
        user_id => $user_id,
        operator => $operator,
    }, undef);
}

sub _duplicate_report {
    my ($self, $schema, $parsed, $upload_info) = @_;

    my $timestamp = $self->_timestamp_without_timezone($upload_info->{flight_timestamp});
    my $report = {
        checked_observation_count => 0,
        existing_observation_count => 0,
        same_value_count => 0,
        changed_value_count => 0,
        file_duplicate_count => 0,
        file_duplicates => [],
        examples => [],
        timestamp => $timestamp || '',
        file_md5 => $upload_info->{file_md5} || '',
    };
    return $report unless $timestamp;

    my $dbh = $schema->storage->dbh;
    my %trait_id_by_name;
    for my $trait (@{ $parsed->{variables} || [] }) {
        my $row = eval { SGN::Model::Cvterm->get_cvterm_row_from_trait_name($schema, $trait) };
        next unless $row;
        $trait_id_by_name{$trait} = $row->cvterm_id;
    }

    my @units = @{ $parsed->{units} || [] };
    my %stock_id_by_name;
    if (@units) {
        my $placeholders = join(',', ('?') x @units);
        my $sth = $dbh->prepare("select stock_id, uniquename from stock where uniquename in ($placeholders)");
        $sth->execute(@units);
        while (my ($stock_id, $uniquename) = $sth->fetchrow_array) {
            $stock_id_by_name{$uniquename} = $stock_id;
        }
    }

    my @stock_ids = values %stock_id_by_name;
    my @trait_ids = values %trait_id_by_name;
    my %existing;
    if (@stock_ids && @trait_ids) {
        my $stock_placeholders = join(',', ('?') x @stock_ids);
        my $trait_placeholders = join(',', ('?') x @trait_ids);
        my $sql = qq{
            select stock.stock_id,
                   stock.uniquename,
                   phenotype.cvalue_id,
                   cvterm.name || '|' || db.name || ':' || dbxref.accession as trait_name,
                   phenotype.value,
                   phenotype.phenotype_id,
                   phenotype.collect_date
            from phenotype
            join nd_experiment_phenotype using(phenotype_id)
            join nd_experiment using(nd_experiment_id)
            join nd_experiment_stock using(nd_experiment_id)
            join stock using(stock_id)
            join cvterm on phenotype.cvalue_id = cvterm.cvterm_id
            join dbxref on cvterm.dbxref_id = dbxref.dbxref_id
            join db on dbxref.db_id = db.db_id
            where stock.stock_id in ($stock_placeholders)
              and phenotype.cvalue_id in ($trait_placeholders)
              and phenotype.collect_date = ?::timestamp
        };
        my $sth = $dbh->prepare($sql);
        $sth->execute(@stock_ids, @trait_ids, $timestamp);
        while (my ($stock_id, $stock_name, $trait_id, $trait_name, $value, $phenotype_id, $collect_date) = $sth->fetchrow_array) {
            push @{ $existing{"$stock_id:$trait_id"} }, {
                stock_name => $stock_name,
                trait_name => $trait_name,
                value => defined $value ? $value : '',
                phenotype_id => $phenotype_id,
                collect_date => "$collect_date",
            };
        }
    }

    for my $unit (@units) {
        my $stock_id = $stock_id_by_name{$unit};
        next unless $stock_id;
        for my $trait (@{ $parsed->{variables} || [] }) {
            my $trait_id = $trait_id_by_name{$trait};
            next unless $trait_id;
            my $observations = $parsed->{data}{$unit}{$trait} || [];
            for my $observation (@$observations) {
                next unless $observation;
                my $incoming_value = $observation->[0];
                next unless defined $incoming_value;
                $report->{checked_observation_count}++;
                my $matches = $existing{"$stock_id:$trait_id"} || [];
                next unless @$matches;
                $report->{existing_observation_count}++;
                my $first = $matches->[0];
                if ($self->_values_equal($incoming_value, $first->{value})) {
                    $report->{same_value_count}++;
                } else {
                    $report->{changed_value_count}++;
                }
                if (@{ $report->{examples} } < 20) {
                    push @{ $report->{examples} }, {
                        unit => $unit,
                        trait => $trait,
                        incoming_value => "$incoming_value",
                        existing_value => $first->{value},
                        phenotype_id => $first->{phenotype_id},
                    };
                }
            }
        }
    }

    if ($upload_info->{file_md5}) {
        my $sth = $dbh->prepare(
            q{
                select file_id, basename, dirname
                from metadata.md_files
                where md5checksum = ?
                order by file_id desc
                limit 10
            }
        );
        $sth->execute($upload_info->{file_md5});
        while (my ($file_id, $basename, $dirname) = $sth->fetchrow_array) {
            $report->{file_duplicate_count}++;
            push @{ $report->{file_duplicates} }, {
                file_id => $file_id,
                basename => $basename || '',
                dirname => $dirname || '',
            };
        }
    }

    return $report;
}

sub _can_import_duplicate_report {
    my ($self, $report) = @_;
    my @blocks;
    if (($report->{changed_value_count} || 0) > 0) {
        push @blocks, 'Changed-value duplicates were found for this flight timestamp.';
    }
    if (($report->{existing_observation_count} || 0) > 0) {
        push @blocks, 'Existing observations were found for this flight timestamp.';
    }
    if (($report->{file_duplicate_count} || 0) > 0) {
        push @blocks, 'A file with the same checksum already exists in archived phenotype metadata.';
    }
    return (!@blocks, join(' ', @blocks));
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

sub _file_md5 {
    my ($self, $path) = @_;
    return '' unless $path;
    open(my $fh, '<', $path) or return '';
    binmode($fh);
    my $ctx = Digest::MD5->new;
    $ctx->addfile($fh);
    close $fh;
    return $ctx->hexdigest;
}

sub _archive_upload_file {
    my ($self, $c, $upload_info) = @_;
    my $source = $upload_info->{tempname};
    return ('', 'Uploaded Solvi file is no longer available for archiving.') unless $source && -f $source;

    my $archive_root = $c->config->{archive_path} || $c->config->{tempfiles_base} || $c->config->{basepath};
    my $archive_dir = File::Spec->catdir($archive_root, 'seedquest_solvi_uploads');
    eval { make_path($archive_dir) unless -d $archive_dir; };
    if ($@) {
        return ('', "Could not create Solvi archive directory: $@");
    }

    my $timestamp = $self->_metadata_timestamp();
    $timestamp =~ s/[:]/-/g;
    my $safe_filename = $self->_safe_filename($upload_info->{filename});
    my $target = File::Spec->catfile($archive_dir, $timestamp . '-' . $safe_filename);
    if (!copy($source, $target)) {
        return ('', "Could not archive uploaded Solvi file: $!");
    }
    return ($target, undef);
}

sub _safe_filename {
    my ($self, $filename) = @_;
    $filename ||= 'solvi_upload.csv';
    $filename =~ s/.*[\/\\]//;
    $filename =~ s/[^A-Za-z0-9._-]+/_/g;
    $filename =~ s/\A[._-]+//;
    return $filename || 'solvi_upload.csv';
}

sub _resolve_flight_timestamp {
    my ($self, $submitted, $parsed_date, $required) = @_;

    my $value = defined $submitted ? $submitted : '';
    $value =~ s/^\s+|\s+$//g;
    if (!$value && $parsed_date) {
        $value = $parsed_date . 'T00:00';
    }
    if (!$value) {
        return ('', '', $required ? 'Flight timestamp is required before write verification.' : undef);
    }

    if ($value =~ /^(\d{4})-(\d{2})-(\d{2})$/) {
        return ("$1-$2-$3 00:00:00+0000", "$1-$2-$3" . 'T00:00', undef);
    }
    if ($value =~ /^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2}))?(?:\.\d+)?(?:Z|([+-]\d{2}:?\d{2}))?$/) {
        my ($year, $month, $day, $hour, $minute, $second, $zone) = ($1, $2, $3, $4, $5, $6 || '00', $7 || '+0000');
        $zone =~ s/://g;
        return ("$year-$month-$day $hour:$minute:$second$zone", "$year-$month-$day" . "T$hour:$minute", undef);
    }

    return ('', '', 'Flight timestamp must be a date or date-time value.');
}

sub _apply_flight_timestamp {
    my ($self, $parsed, $timestamp) = @_;
    return unless $timestamp;
    for my $unit (@{ $parsed->{units} || [] }) {
        for my $trait (@{ $parsed->{variables} || [] }) {
            my $observations = $parsed->{data}{$unit}{$trait} || [];
            for my $observation (@$observations) {
                next unless $observation;
                $observation->[1] = $timestamp;
            }
        }
    }
}

sub _timestamp_without_timezone {
    my ($self, $timestamp) = @_;
    return '' unless $timestamp;
    $timestamp =~ s/T/ /;
    $timestamp =~ s/(?:Z|[+-]\d{2}:?\d{2})$//;
    $timestamp .= ':00' if $timestamp =~ /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$/;
    return $timestamp;
}

sub _clean_text_param {
    my ($self, $c, $name) = @_;
    my $value = $c->req->param($name) || '';
    $value =~ s/^\s+|\s+$//g;
    $value = substr($value, 0, 120);
    return $value;
}

sub _values_equal {
    my ($self, $left, $right) = @_;
    $left = '' unless defined $left;
    $right = '' unless defined $right;
    if ($left =~ /^[+-]?(?:\d+(?:[.]\d*)?|[.]\d+)(?:[eE][+-]?\d+)?$/ && $right =~ /^[+-]?(?:\d+(?:[.]\d*)?|[.]\d+)(?:[eE][+-]?\d+)?$/) {
        return abs($left - $right) < 0.0000001 ? 1 : 0;
    }
    return "$left" eq "$right" ? 1 : 0;
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
