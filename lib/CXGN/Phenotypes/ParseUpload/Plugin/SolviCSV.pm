package CXGN::Phenotypes::ParseUpload::Plugin::SolviCSV;

use Moose;
use SeedQuest::Solvi::Parser;

sub name {
    return 'solvi csv';
}

sub validate {
    my $self = shift;
    my $filename = shift;

    my $parsed = SeedQuest::Solvi::Parser->new()->parse_file($filename);
    return { error => $parsed->{error} } if $parsed->{error};
    return 1;
}

sub parse {
    my $self = shift;
    my $filename = shift;
    my $timestamp_included = shift;
    my $data_level = shift;
    my $schema = shift;
    my $zipfile = shift;
    my $user_id = shift;
    my $c = shift;

    my $trait_map = {};
    if ($c && $c->can('config') && $c->config->{seedquest_solvi_trait_map}) {
        $trait_map = $c->config->{seedquest_solvi_trait_map};
    }

    my $parsed = SeedQuest::Solvi::Parser->new(trait_map => $trait_map)->parse_file($filename);
    return { error => $parsed->{error} } if $parsed->{error};

    return {
        data => $parsed->{data},
        units => $parsed->{units},
        variables => $parsed->{variables},
    };
}

1;
