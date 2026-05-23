package SeedQuest::Solvi::Parser;

use strict;
use warnings;
use Text::CSV;

my %STAT = (
    'average' => 'mean',
    'median' => 'median',
    'standard deviation' => 'stdev',
);

my %INDEX = (
    'NDVI'   => 'Canopy NDVI',
    'NDRE'   => 'Canopy NDRE',
    'OSAVI'  => 'Canopy OSAVI',
    'GRVI'   => 'Canopy GRVI',
    'NIR'    => 'Canopy NIR reflectance',
    'HEIGHT' => 'Canopy height (cm)',
);

my %DEFAULT_TRAIT_MAP = (
    'ndvi_mean'   => 'Canopy NDVI - mean|SQ:SOLVI_000001',
    'ndvi_median' => 'Canopy NDVI - median|SQ:SOLVI_000002',
    'ndvi_stdev'  => 'Canopy NDVI - stdev|SQ:SOLVI_000003',
    'ndre_mean'   => 'Canopy NDRE - mean|SQ:SOLVI_000004',
    'ndre_median' => 'Canopy NDRE - median|SQ:SOLVI_000005',
    'ndre_stdev'  => 'Canopy NDRE - stdev|SQ:SOLVI_000006',
    'osavi_mean'   => 'Canopy OSAVI - mean|SQ:SOLVI_000007',
    'osavi_median' => 'Canopy OSAVI - median|SQ:SOLVI_000008',
    'osavi_stdev'  => 'Canopy OSAVI - stdev|SQ:SOLVI_000009',
    'grvi_mean'   => 'Canopy GRVI - mean|SQ:SOLVI_000010',
    'grvi_median' => 'Canopy GRVI - median|SQ:SOLVI_000011',
    'grvi_stdev'  => 'Canopy GRVI - stdev|SQ:SOLVI_000012',
    'nir_mean'   => 'Canopy NIR reflectance - mean|SQ:SOLVI_000013',
    'nir_median' => 'Canopy NIR reflectance - median|SQ:SOLVI_000014',
    'nir_stdev'  => 'Canopy NIR reflectance - stdev|SQ:SOLVI_000015',
    'height_mean'   => 'Canopy height (cm) - mean|SQ:SOLVI_000016',
    'height_median' => 'Canopy height (cm) - median|SQ:SOLVI_000017',
    'height_stdev'  => 'Canopy height (cm) - stdev|SQ:SOLVI_000018',
);

my %HOMOGLYPH = (
    "\x{0410}" => 'A', "\x{0412}" => 'B', "\x{0415}" => 'E',
    "\x{041A}" => 'K', "\x{041C}" => 'M', "\x{041D}" => 'H',
    "\x{041E}" => 'O', "\x{0420}" => 'P', "\x{0421}" => 'C',
    "\x{0422}" => 'T', "\x{0425}" => 'X', "\x{0430}" => 'a',
    "\x{0435}" => 'e', "\x{043E}" => 'o', "\x{0440}" => 'p',
    "\x{0441}" => 'c', "\x{0445}" => 'x', "\x{0443}" => 'y',
    "\x{043A}" => 'k', "\x{043C}" => 'm', "\x{043D}" => 'h',
    "\x{0442}" => 't', "\x{0432}" => 'b',
);

sub new {
    my ($class, %args) = @_;
    return bless {
        trait_map => $args{trait_map} || {},
    }, $class;
}

sub parse_file {
    my ($self, $filename, %args) = @_;

    my $flight_date = $args{flight_date}
        || $self->_date_from_filename($args{source_filename})
        || $self->_date_from_filename($filename);
    my $timestamp = $flight_date ? "$flight_date 00:00:00+0000" : '';

    my $csv = Text::CSV->new({
        binary => 1,
        auto_diag => 0,
        allow_loose_quotes => 1,
    });

    open(my $fh, '<:encoding(UTF-8)', $filename)
        or return { error => "Could not open Solvi CSV: $!" };

    my $header = $csv->getline($fh);
    unless ($header && @$header) {
        close $fh;
        return { error => 'Solvi CSV is missing a header row.' };
    }

    my ($zone_col, @plan) = $self->_build_plan($header);
    if (!defined $zone_col) {
        close $fh;
        return { error => 'Solvi CSV must contain a Zone column.' };
    }
    unless (@plan) {
        close $fh;
        return { error => 'Solvi CSV does not contain any supported metric columns.' };
    }

    my (%traits_seen, @traits);
    for my $p (@plan) {
        next if $traits_seen{$p->{trait}}++;
        push @traits, $p->{trait};
    }

    my (%data, %units_seen, @units, %row_count);
    my ($dropped_buffers, $row_number) = (0, 1);

    while (my $row = $csv->getline($fh)) {
        $row_number++;
        my $zone = $self->_trim($row->[$zone_col]);
        next if !defined $zone || $zone eq '';
        if ($self->_is_buffer($zone)) {
            $dropped_buffers++;
            next;
        }

        $zone = $self->_fold_homoglyphs($zone);
        $row_count{$zone}++;
        if ($row_count{$zone} > 1) {
            close $fh;
            return {
                error => "Solvi Zone '$zone' appears more than once. Re-export using unique Breedbase plot names.",
            };
        }

        $units_seen{$zone} = 1;
        push @units, $zone;

        for my $p (@plan) {
            my $value = $self->_trim($row->[$p->{col}]);
            next if !defined $value || $value eq '';
            next unless $value =~ /^[+-]?(?:\d+(?:[.]\d*)?|[.]\d+)(?:[eE][+-]?\d+)?$/;
            $value = $value + 0;
            $value = $value * 100 if $p->{height} && $p->{unit} eq 'm';
            push @{ $data{$zone}->{ $p->{trait} } }, [ $value, $timestamp ];
        }
    }
    my $parse_error = $csv->error_diag();
    close $fh;

    if ($parse_error && "$parse_error" !~ /^2012/ && "$parse_error" !~ /^EOF - End of data/) {
        return { error => "Could not parse Solvi CSV near row $row_number: $parse_error" };
    }
    unless (@units) {
        return { error => 'Solvi CSV has no non-buffer plot rows.' };
    }

    return {
        data => \%data,
        units => \@units,
        variables => \@traits,
        flight_date => $flight_date,
        dropped_buffers => $dropped_buffers,
    };
}

sub _build_plan {
    my ($self, $header) = @_;
    my ($zone_col, @plan);

    for my $i (0 .. $#$header) {
        my $column = $self->_trim($header->[$i]);
        next if !defined $column || $column eq '';
        if (lc($column) eq 'zone') {
            $zone_col = $i;
            next;
        }

        my $unit = '';
        $unit = lc($1) if $column =~ /\(([^)]*)\)\s*$/;
        (my $base = $column) =~ s/\s*\([^)]*\)\s*$//;
        next unless $base =~ /^(\S+)\s+(.+)$/;

        my ($index, $stat_phrase) = (uc($1), lc($2));
        next unless exists $INDEX{$index} && exists $STAT{$stat_phrase};

        my $trait = $self->_trait_name($index, $STAT{$stat_phrase});
        push @plan, {
            col => $i,
            trait => $trait,
            height => $index eq 'HEIGHT' ? 1 : 0,
            unit => $unit,
        };
    }

    return ($zone_col, @plan);
}

sub _trait_name {
    my ($self, $index, $stat) = @_;
    my $key = lc($index) . '_' . $stat;
    return $self->{trait_map}{$key} if $self->{trait_map}{$key};
    return $DEFAULT_TRAIT_MAP{$key} if $DEFAULT_TRAIT_MAP{$key};
    return "$INDEX{$index} - $stat";
}

sub _date_from_filename {
    my ($self, $filename) = @_;
    return '' unless defined $filename;
    my %months = (
        JAN => '01', FEB => '02', MAR => '03', APR => '04',
        MAY => '05', JUN => '06', JUL => '07', AUG => '08',
        SEP => '09', OCT => '10', NOV => '11', DEC => '12',
    );
    if ($filename =~ /(\d{1,2})[_.-](JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)[_.-](\d{4})/i) {
        my ($day, $month, $year) = ($1, $months{uc($2)}, $3);
        return '' unless $self->_valid_date($year, $month, $day);
        return sprintf('%04d-%02d-%02d', $year, $month, $day);
    }
    if ($filename =~ /(\d{4})-(\d{2})-(\d{2})/) {
        return '' unless $self->_valid_date($1, $2, $3);
        return "$1-$2-$3";
    }
    return '';
}

sub _valid_date {
    my ($self, $year, $month, $day) = @_;
    return 0 unless defined $year && defined $month && defined $day;
    return 0 unless $year =~ /^\d{4}$/ && $month =~ /^\d{1,2}$/ && $day =~ /^\d{1,2}$/;
    return 0 if $year < 1900 || $year > 2100 || $month < 1 || $month > 12 || $day < 1;
    my @days_in_month = (31, $self->_is_leap_year($year) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31);
    return $day <= $days_in_month[$month - 1] ? 1 : 0;
}

sub _is_leap_year {
    my ($self, $year) = @_;
    return 1 if $year % 400 == 0;
    return 0 if $year % 100 == 0;
    return $year % 4 == 0 ? 1 : 0;
}

sub _is_buffer {
    my ($self, $value) = @_;
    my $folded = lc($self->_fold_homoglyphs($value));
    $folded =~ s/\s+//g;
    return $folded =~ /^buf+e?r$/ ? 1 : 0;
}

sub _fold_homoglyphs {
    my ($self, $value) = @_;
    return '' unless defined $value;
    my $out = '';
    for my $ch (split //, $value) {
        $out .= exists $HOMOGLYPH{$ch} ? $HOMOGLYPH{$ch} : $ch;
    }
    return $out;
}

sub _trim {
    my ($self, $value) = @_;
    return undef unless defined $value;
    $value =~ s/\A\x{FEFF}//;
    $value =~ s/^\s+|\s+$//g;
    $value =~ s/\A\x{FEFF}//;
    return $value;
}

1;
