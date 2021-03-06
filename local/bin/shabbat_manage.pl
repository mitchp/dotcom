#!/usr/bin/perl -w

########################################################################
#
# Copyright (c) 2014  Michael J. Radwin.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or
# without modification, are permitted provided that the following
# conditions are met:
#
#  * Redistributions of source code must retain the above
#    copyright notice, this list of conditions and the following
#    disclaimer.
#
#  * Redistributions in binary form must reproduce the above
#    copyright notice, this list of conditions and the following
#    disclaimer in the documentation and/or other materials
#    provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND
# CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
# INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
# NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
# OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
########################################################################

eval 'exec /usr/bin/perl -w -S $0 ${1+"$@"}'
    if 0; # not running under some shell

use lib "/home/hebcal/local/share/perl";
use lib "/home/hebcal/local/share/perl/site_perl";

use strict;
use DBI ();
use Hebcal ();
use Mail::Internet ();
use Email::Valid ();
use MIME::Base64 ();
use Config::Tiny;

my $Config = Config::Tiny->read($Hebcal::CONFIG_INI_PATH)
    or die "$Hebcal::CONFIG_INI_PATH: $!\n";
my $DBHOST = $Config->{_}->{"hebcal.mysql.host"};
my $DBUSER = $Config->{_}->{"hebcal.mysql.user"};
my $DBPASS = $Config->{_}->{"hebcal.mysql.password"};
my $DBNAME = $Config->{_}->{"hebcal.mysql.dbname"};

my $site = "hebcal.com";
my $DSN = "DBI:mysql:database=$DBNAME;host=$DBHOST";

my $err_notsub =
"The email address used to send your message is not subscribed
to the Shabbat candle lighting time list.";
my $err_useweb =
"We currently cannot handle email subscription requests.  Please
use the web interface to subscribe:

  http://www.$site/email";

my $message = new Mail::Internet \*STDIN;
my $header = $message->head();

my $to = $header->get("To");
if ($to) {
    chomp($to);
    if ($to =~ /^[^<]*<([^>]+)>/) {
	$to = $1;
    }
    if (Email::Valid->address($to)) {
	$to = Email::Valid->address($to);
    } else {
	warn $Email::Valid::Details;
    }
}

my $from = $header->get("From");
if ($from) {
    chomp($from);
    if ($from =~ /^[^<]*<([^>]+)>/) {
	$from = $1;
    }
    if (Email::Valid->address($from)) {
	$from = lc(Email::Valid->address($from));
    } else {
	warn $Email::Valid::Details;
    }
}

unless ($from) {
    shabbat_log(0, "missing_from");
    exit(0);
}

unless (defined $to) {
    shabbat_log(0, "needto");
    exit(0);
}

if ($to =~ /shabbat-subscribe/i) {
    shabbat_log(0, "subscribe_useweb");
    error_email($err_useweb);
    exit(0);
} elsif ($to =~ /shabbat-unsubscribe(?:[-+])([^\@]+)\@/i) {
    my $email_id = $1;
    unsubscribe($from, $email_id);
} elsif ($to =~ /shabbat-unsubscribe\@/i) {
    unsubscribe($from, undef);
} else {
    shabbat_log(0, "badto");
}
exit(0);


sub unsubscribe
{
    my($email,$email_id) = @_;

    my $dbh = DBI->connect($DSN, $DBUSER, $DBPASS);

    my $sql = "SELECT email_status,email_id FROM hebcal_shabbat_email";
    if ($email_id) {
        $sql .= " WHERE email_id = '$email_id'";
    } else {
        $sql .= " WHERE email_address = '$email'";
    }
    my $sth = $dbh->prepare($sql);
    my $rv = $sth->execute
	or die "can't execute the query: " . $sth->errstr;
    my($status,$encoded) = $sth->fetchrow_array;
    $sth->finish;

    unless ($status) {
	shabbat_log(0, "unsub_notfound");

	$dbh->disconnect;

	error_email($err_notsub);
	return 0;
    }

    if ($status eq "unsubscribed") {
	shabbat_log(0, "unsub_twice");

	$dbh->disconnect;

	error_email($err_notsub);
	return 0;
    }

    shabbat_log(1, "unsub");

    $sql = <<EOD
UPDATE hebcal_shabbat_email
SET email_status='unsubscribed'
WHERE email_id = '$encoded'
EOD
;
    $dbh->do($sql);
    $dbh->disconnect;

    my($body) = qq{Hello,

Per your request, you have been removed from the weekly
Shabbat candle lighting time list.

Regards,
$site};

    my %headers =
	(
	 "From" =>
	 "Hebcal <shabbat-owner\@$site>",
	 "To" => $email,
	 "Content-Type" => "text/plain",
	 "Subject" => "You have been unsubscribed from hebcal",
	 );

    if ($header) {
	my $mid = $header->get("Message-Id");
	if ($mid) {
	    chomp($mid);
	    $headers{"References"} = $headers{"In-Reply-To"} = $mid;
	}
    }

    Hebcal::sendmail_v2(Hebcal::shabbat_return_path($email),\%headers,$body);
}

sub error_email
{
    my($error) = @_;

    my $email = $from;
    return 0 unless $email;

    my $addr = ($to ? $to : "shabbat-unsubscribe\@$site");
    while(chomp($error)) {}
    my($body) = qq{Sorry,

We are unable to process the message from <$email>
to <$addr>.

$error

Regards,
$site};

    my %headers =
	(
	 "From" =>
	 "Hebcal <shabbat-owner\@$site>",
	 "To" => $email,
	 "Content-Type" => "text/plain",
	 "Subject" => "Unable to process your message",
	 );

    if ($header) {
	my $mid = $header->get("Message-Id");
	if ($mid) {
	    chomp($mid);
	    $headers{"References"} = $headers{"In-Reply-To"} = $mid;
	}
    }

    Hebcal::sendmail_v2(Hebcal::shabbat_return_path($email),\%headers,$body);
}

sub shabbat_log
{
    my($status,$code) = @_;
    if (open(LOG, ">>/home/hebcal/local/var/log/subscribers.log"))
    {
	my $t = time();
	print LOG "status=$status from=$from to=$to code=$code time=$t\n";
	close(LOG);
    }
}
