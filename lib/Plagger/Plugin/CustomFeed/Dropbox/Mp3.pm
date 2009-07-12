package Plagger::Plugin::CustomFeed::Dropbox::Mp3;

use strict;
use warnings;

use base qw(Plagger::Plugin);
use Plagger::Date;
use Plagger::Feed;
use Plagger::Util;
use Plagger::Enclosure;

use XML::LibXML;
use HTML::TokeParser::Simple;
use DateTime::Format::DateParse;

sub register {
    my ($self, $context) = @_;

    # エントリーロード時のフックを設定
    $context->register_hook(
        $self,
        'subscription.load' => \&load,
    );
}

sub load {
    my ($self, $context) = @_;

    my $ym   = Plagger::Date->now()->strftime("%y%m");
    my $feed = Plagger::Feed->new();
    $feed->aggregator(sub { $self->aggregate($context, $ym); });
    $context->subscription->add($feed);
}

sub aggregate {
    my ($self, $context, $ym) = @_;

    my $feed = Plagger::Feed->new();
    my $renewaltime = Plagger::Date->now();
    $renewaltime->set_locale("ja_JP");

    $feed->link($self->conf->{url});
    $feed->title($self->conf->{title});
    $feed->description($self->conf->{desc});

    # Feedをパース
    my $items = $self->parse(
        Plagger::Util::load_uri(URI->new($self->conf->{url}))
    );

    # パースしたFeedのエントリたちをRSSに登録していく
    for my $item (@$items) {
        my $entry = Plagger::Entry->new();
        $entry->title($item->{title});
        $entry->link($item->{link});
        $entry->date($item->{datetime});

        my $enclosure = Plagger::Enclosure->new();
        $enclosure->url($item->{link});
        $enclosure->auto_set_type();
        $entry->add_enclosure($enclosure);

        $feed->add_entry($entry);
    }

    $context->update->add($feed);
}

sub parse {
    my ($self, $content) = @_;
    my $list = [];

    # XMLパース
    my $parser = XML::LibXML->new();
    my $dom = $parser->parse_string($content);

    my @nodes_item = $dom->findnodes('//item');

    # エントリーからHTMLタグ(Aタグ)のhref部分を抜き出してリストに追加
    foreach my $node_item (@nodes_item) {

        my $action = $node_item->findvalue('title');
        next if ($action !~ /added/);

        my $content = $node_item->findvalue('description');

        # UTC形式で書かれたpubDateをJSTに変換(YYYYMMDDhhmmss)
        my $pubDate = $node_item->findvalue('pubDate');
        my $dt = DateTime::Format::DateParse->parse_datetime($pubDate);
        $dt->set_time_zone('Asia/Tokyo');
        my $datetime = sprintf("%04d%02d%02d%02d%02d%02d",
            $dt->year,
            $dt->month,
            $dt->day,
            $dt->hour,
            $dt->minute,
            $dt->second,
        );

        my $html_parser = HTML::TokeParser::Simple->new(
            string => $content
        );
        while(my $token = $html_parser->get_token) {
            if ($token->is_start_tag('a')) {
                my $title = $token->get_attr('title');
                next if ($title !~ /\.mp3$/);
                if ($title =~ /(.+)\.mp3$/) {
                    $title = $1;
                }

                my $href = $token->get_attr('href');

                push (@$list, {
                    datetime => $datetime,
                    title    => $title,
                    link     => $href,
                });
            }
        }
    }

    @$list = sort { $b->{datetime} cmp $a->{datetime} } @$list;
    $list;
}

1;
