#!/usr/bin/perl
use strict;
use warnings;
use JSON;
use YAML::XS 'LoadFile';
use LWP::UserAgent;
use Template;

my $config = LoadFile('config.yaml') or die "Failed to load configuration file: 'config.yaml'\n";
my $repositories = $config->{repositories} or die "No repositories specified in config file.\n";

my $ua = LWP::UserAgent->new;
$ua->default_header('Accept' => 'application/vnd.github+json');
$ua->default_header('Authorization' => "token $config->{github_token}");

my $template = Template->new({
    INCLUDE_PATH => '.',
    INTERPOLATE  => 1,
}) or die "$Template::ERROR\n";

my @repositories_data;

foreach my $repo (@$repositories)
{
    my $releases_url = "https://api.github.com/repos/$repo/releases";
    my $repo_url = "https://api.github.com/repos/$repo";

    my $repo_response = $ua->get($repo_url);
    my ($repo_name, $repo_description);

    if ($repo_response->is_success)
    {
        my $repo_data = decode_json($repo_response->decoded_content);
        $repo_name = "$repo_data->{owner}{login}/$repo_data->{name}" || $repo;
        $repo_description = $repo_data->{description} || "No description available.";
    }
    else
    {
        $repo_name = $repo;
        $repo_description = "Failed to fetch repository details.";
    }

    my @releases_data;

    my $response = $ua->get($releases_url);

    if ($response->is_success)
    {
        my $releases = decode_json($response->decoded_content);

        if (@$releases > 0)
        {
            # Process the latest 3 releases
            for my $release (@$releases[0..$config->{"max-releases"}-1])
            {
                my $release_name = $release->{name} || "Unnamed Release";
                my $apk_url;

                # Find the first .apk asset
                if (my $assets = $release->{assets})
                {
                    for my $asset (@$assets)
                    {
                        my $asset_name = $asset->{name};
                        my $asset_url = $asset->{browser_download_url};

                        if ($asset_name =~ /\.apk$/)
                        {
                            $apk_url = $asset_url;
                            last;
                        }
                    }
                }

                if ($apk_url)
                {
                    push @releases_data,
                    {
                        name => $release_name,
                        url  => $apk_url,
                    };
                }
            }
        }
    }

    push @repositories_data,
    {
        name        => $repo_name,
        description => $repo_description,
        releases    => \@releases_data,
    };
}

my $vars =
{
    repositories => \@repositories_data,
    title        => $config->{title},
    css_file     => "style.css",
};

$template->process('template.tt2', $vars, $config->{output}) or die $template->error(), "\n";
