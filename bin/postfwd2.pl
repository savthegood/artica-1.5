#!/usr/bin/perl -T -w

############################
package postfwd2::basic;

use warnings;
use strict;
use IO::Socket qw(SOCK_STREAM);
use Sys::Syslog qw(:DEFAULT setlogsock);
# export
use Exporter qw(import);
our @EXPORT = qw(
	%postfwd_settings %postfwd_patterns
	&uniq &init_log &log_info &log_note
	&log_warn &log_err &log_crit
);
our @EXPORT_OK = qw(
	%postfwd_commands
	&wantsdebug &hash_to_list
	&hash_to_str &str_to_hash
	&check_inet &check_unix
	&ts $TIMEHIRES
);
# use Time::HiRes if available
our($TIMEHIRES);
BEGIN {
	eval { require Time::HiRes };
	$TIMEHIRES = ($@) ? 0 : (Time::HiRes->VERSION || 'available');
};


# basics
our $NAME	= "postfwd2";
our $VERSION	= "1.30";
our $DEFAULT	= 'DUNNO';

# change this, to match your POD requirements
# we need pod2text for the -m switch (manual)
$ENV{PATH}                      = "/bin:/usr/bin:/usr/local/bin";
$ENV{ENV}                       = "";
our($cmd_manual)                = "pod2text";
our($cmd_pager)                 = "more";

my $sepreq	= '///';
my $seplst	= ':::';
my $seplim	= '~~~';
my $nounixsock	= ($^O eq 'solaris');

# program settings
our %postfwd_settings = (
	base => {
		user             => 'nobody',
		group            => 'nobody',
		#setsid           => 1,
		log_level        => 2,
		log_file         => 'Sys::Syslog',
		syslog_ident     => "$NAME",
		#chroot           => $net_chroot ? $net_chroot : undef,
		umask		 => "0177",
	},
	master => {
		pid_file         => "/var/tmp/$NAME-master.pid",
		watchdog	 => 60,
		failures	 => 7,
		respawn		 => 4,
		daemons		 => [ 'cache', 'server' ],
	},
	cache => {
		commandline	 => " ".$NAME."::cache",
		syslog_ident     => "$NAME/cache",
		host		 => (($nounixsock) ? "127.0.0.1" : ""),
		port             => (($nounixsock) ? "10043" : "/var/tmp/$NAME-cache.socket"),
		proto		 => (($nounixsock) ? "tcp" : "unix"),
		check		 => (($nounixsock) ? \&check_inet : \&check_unix),
		umask		 => "0177",
	},
	server => {
		commandline	 => " ".$NAME."::policy",
		syslog_ident     => "$NAME/policy",
		host             => '127.0.0.1',
		port             => 10045,
		proto            => "tcp",
		check		 => \&check_inet,
		umask		 => "0111",
		# child control
		#check_for_dead         => 30,
		#check_for_waiting      => 10,
		min_spare_servers       => 5,
		min_servers             => 10,
		max_spare_servers       => 50,
		max_servers             => 100,
		max_requests            => 1000,
		child_communication     => 1, # children report data to parent for summary
		leave_children_open_on_hup => 1,  # children should finish their work
	},
	syslog => {
		nolog		=> 0,
		noidlestats	=> 0,
		norulestats	=> 0,
		name		=> $NAME,
		facility	=> 'mail',
		options		=> 'pid',
		# allow "umlaute" ;)
		#unsafe_charset	=> qr/[^\x20-\x7E,\x80-\xFE]/,
		unsafe_charset	=> qr/[^\x20-\x7E]/,
		unsafe_version  => (not(defined $Sys::Syslog::VERSION) or $Sys::Syslog::VERSION lt '0.15'),
		perfmon   	=> 0,
		stdout		=> 0,
	},
	timeout => {
		rule		=> 40,
		cache		=> 3,
		server		=> 3,
		config		=> 4,
	},
	request => {
		ttl		=> 600,
		cleanup		=> 600,
		no_sender	=> 0,
		rdomain_only	=> 0,
		no_size		=> 0,
		nolog		=> 0,
		noparent	=> 0,
	},
	dns => {
		disable		=> 0,
		nolog		=> 0,
		noparent	=> 1,
		anylog		=> 0,
		async_txt	=> 0,
		timeout		=> 14,
		max_timeout	=> 10,
		max_interval	=> 1200,
		ttl		=> 3600,
		cleanup		=> 600,
		mask		=> '^127\.',
		max_ns_lookups	=> 100,
		max_mx_lookups	=> 100,
	},
	rate => {
		cleanup		=> 600,
		noparent	=> 0,
	},
	scores => {
		"5.0"		=> "554 5.7.1 ".$NAME." score exceeded",
	},
	debug     => {
		#all		=> 0,
		#verbose	=> 0,
		#cache		=> 0,
		#rates		=> 0,
		#config		=> 0,
		#cache		=> 0,
		#getcache	=> 0,
		#setcache	=> 0,
		#dns		=> 0,
		#getdns		=> 0,
		#setdns		=> 0,
	},
	name	   => $NAME,
	version    => $VERSION,
	default    => $DEFAULT,
	daemon     => 1,
	manual     => $cmd_manual,
	pager      => $cmd_pager,
	sepreq     => $sepreq,
	seplst     => $seplst,
	seplim     => $seplim,
	summary    => 600,
	instant    => 0,
	verbose    => 0,
	test	   => 0,
	keep_rates => 0,
        timeformat => ( ($TIMEHIRES) ? '%.2f' : '%d' ),
);

# daemon commands
our %postfwd_commands = (
	ping          => 'PING',
	pong          => 'PONG',
	dumpstats     => 'DS',
	dumpcache     => 'DC',
	#wipecache    => 'WC',
	countcache    => 'CN',
	matchcache    => 'MT',
	setcacheitem  => 'SC',
	getcacheitem  => 'GC',
	getcacheval   => 'GV',
	checkrate     => 'CR',
	setrateitem  => 'SR',
	getrateitem  => 'GR',
);

# precompiled patterns
our %postfwd_patterns = (
	ping          => $postfwd_commands{ping},
	pong          => $postfwd_commands{pong},
	keyval	      => qr/^([^=]+)=(.*)$/,
	cntval        => qr/^([^=]+)=(\d+)$/,
	command       => qr/^CMD\s*=/i,
	dumpstats     => qr/^CMD\s*=\s*$postfwd_commands{dumpstats}\s*;\s*$/i,
	dumpcache     => qr/^CMD\s*=\s*$postfwd_commands{dumpcache}\s*;\s*$/i,
	#wipecache    => qr/^CMD\s*=\s*$postfwd_commands{wipecache}\s*;\s*$/i,
	countcache    => qr/^CMD\s*=\s*$postfwd_commands{countcache}\s*;\s*TYPE\s*=\s*(.*?)\s*$/i,
	matchcache    => qr/^CMD\s*=\s*$postfwd_commands{matchcache}\s*;\s*TYPE\s*=\s*(.*?)\s*$/i,
	setcacheitem  => qr/^CMD\s*=\s*$postfwd_commands{setcacheitem}\s*;\s*TYPE\s*=\s*([^;]+)\s*;\s*ITEM\s*=\s*(.*?)\s*$sepreq\s*(.*?)\s*$/i,
	getcacheitem  => qr/^CMD\s*=\s*$postfwd_commands{getcacheitem}\s*;\s*TYPE\s*=\s*([^;]+)\s*;\s*ITEM\s*=\s*(.*?)\s*$/i,
	getcacheval   => qr/^CMD\s*=\s*$postfwd_commands{getcacheval}\s*;\s*TYPE\s*=\s*([^;]+)\s*;\s*ITEM\s*=\s*(.*?)\s*$sepreq\s*KEY\s*=\s*(.*?)\s*$/i,
	checkrate     => qr/^CMD\s*=\s*$postfwd_commands{checkrate}\s*;\s*TYPE\s*=\s*([^;]+)\s*;\s*ITEM\s*=\s*([^;]+)\s*;\s*SIZE\s*=\s*([^;]+)\s*;\s*RCPT\s*=\s*([^;]+)\s*$/i,
	setrateitem   => qr/^CMD\s*=\s*$postfwd_commands{setrateitem}\s*;\s*TYPE\s*=\s*([^;]+)\s*;\s*ITEM\s*=\s*(.*?)\s*$sepreq\s*(.*?)\s*$/i,
	getrateitem   => qr/^CMD\s*=\s*$postfwd_commands{getrateitem}\s*;\s*TYPE\s*=\s*([^;]+)\s*;\s*ITEM\s*=\s*(.*?)\s*$/i,
);


## SUBS

# prints formatted timestamp
sub ts { return sprintf ($postfwd_settings{timeformat}, $_[0]) };

# takes a list and returns a unified list, keeping given order
sub uniq {
	undef my %uniq;
	return grep(!$uniq{$_}++, @_);
};

# tests debug levels
sub wantsdebug {
	return unless %{$postfwd_settings{debug}};
	foreach (@_) { return 1 if $postfwd_settings{debug}{$_} };
};

# hash -> scalar
sub hash_to_str {
	my %request = @_; my $result  = '';
	map { $result .= $postfwd_settings{sepreq}."$_=".((ref $request{$_} eq 'ARRAY') ? (join $postfwd_settings{seplst}, @{$request{$_}}) : ($request{$_} || '')) } (keys %request);
	return $result;
};

# scalar -> hash
sub str_to_hash {
	my $request = shift; my %result  = ();
	foreach (split $postfwd_settings{sepreq}, $request) {
		next unless m/$postfwd_patterns{keyval}/;
		my @items = split $postfwd_settings{seplst}, $2;
		($#items) ? @{$result{$1}} = @items : $result{$1} = $2;
	}; return %result;
};

# displays hash structure
sub hash_to_list {
	my ($pre, %request) = @_; my @output = ();
	# get longest key
	my $minkey = '-'.(length((sort {length($b) <=> length($a)} (keys %request))[0] || '') + 1);
	while ( my($s, $v) = each %request ) {
		my $r = ref $v;
		if ($r eq 'HASH') {
			push @output, (%{$v})
				? hash_to_list ( sprintf ("%s -> %".$minkey."s", $pre, '%'.$s), %{$v} )
				: sprintf ("%s -> %".$minkey."s -> %s", $pre, '%'.$s, 'undef');
		} elsif ($r eq 'ARRAY') {
			push @output, sprintf ("%s -> %".$minkey."s -> %s", $pre, '@'.$s, ((@{$v}) ? "'".(join ",", @{$v})."'" : 'undef'));
		} elsif ($r eq 'CODE') {
			push @output, sprintf ("%s -> %".$minkey."s -> %s", $pre, '&'.$s, ((defined $v) ? "'".$v."'" : 'undef'));
		} else {
			push @output, sprintf ("%s -> %".$minkey."s -> %s", $pre, '$'.$s, ((defined $v) ? "'".$v."'" : 'undef'));
		};
	};
	return sort { my ($c, $d) = ($a, $b);
		$c =~ tr/$/1/; $c =~ tr/&/2/; $c =~ tr/@/3/; $c =~ tr/%/4/;
		$d =~ tr/$/1/; $d =~ tr/&/2/; $d =~ tr/@/3/; $d =~ tr/%/4/;
		return $c cmp $d; } @output;
};

# Sys::Syslog < 0.15
sub mylogs_old {
	my($prio,$msg) = @_;
	eval { local $SIG{'__DIE__'}; syslog ($prio,$msg) };
};

# Sys::Syslog >= 0.15
sub mylogs_new {
	my($prio,$msg) = @_;
	syslog ($prio,$msg);
};

# Syslog to stdout
sub mylogs_stdout {
	my($prio,$msg) = @_;
	printf STDOUT "[LOG $prio]: $msg\n", @_;
};

# send log message
sub mylogs {
	my($prio,$msg) = @_;
	return if $postfwd_settings{syslog}{nolog};
	# escape unsafe characters
	$msg =~ s/$postfwd_settings{syslog}{unsafe_charset}/?/g;
	$msg =~ s/\%/%%/g;
	&{$postfwd_settings{syslog}{logger}} ($prio,$msg);
};

# short versions
sub log_info { mylogs ('info', @_) };
sub log_note { mylogs ('notice', @_) };
sub log_warn { mylogs ('warning', @_) };
sub log_err  { mylogs ('err', @_) };
sub log_crit { mylogs ('crit', @_) };

# init logging
sub init_log {
	my($logname) = @_;
	$postfwd_settings{syslog}{name} = $logname if $logname;
	$postfwd_settings{syslog}{socktype} = ( $postfwd_settings{syslog}{socktype} || (($postfwd_settings{syslog}{unsafe_version}) ? (($nounixsock) ? 'inet' : 'unix') : 'native') );
	if ($postfwd_settings{syslog}{stdout}) {
		$postfwd_settings{syslog}{logger}   = \&mylogs_stdout;
	} else {
		# syslog init
		$postfwd_settings{syslog}{logger}   = ($postfwd_settings{syslog}{unsafe_version}) ? \&mylogs_old : \&mylogs_new;
		setlogsock $postfwd_settings{syslog}{socktype};
		openlog $postfwd_settings{syslog}{name}, $postfwd_settings{syslog}{options}, $postfwd_settings{syslog}{facility};
	};
	log_info ("set up syslogging Sys::Syslog".((defined $Sys::Syslog::VERSION) ? " version $Sys::Syslog::VERSION" : '') ) if wantsdebug (qw[ all verbose ]);
};

# check: INET
sub check_inet {
	my ($type,$send) = @_;
	if ( my $socket = new IO::Socket::INET (
		PeerAddr => $postfwd_settings{$type}{host},
		PeerPort => $postfwd_settings{$type}{port},
		Proto    => 'tcp',
		Timeout  => $postfwd_settings{timeout}{$type},
		Type     => SOCK_STREAM ) ) {
		$socket->print("$send\r\n");
		$send = $socket->getline();
		chomp($send);
		$socket->close();
	} else {
		warn("can not open socket to $postfwd_settings{$type}{host}:$postfwd_settings{$type}{port}: '$!' '$@'\n");
		undef $send;
	};
	return $send;
};

# check: UNIX
sub check_unix {
	my ($type,$send) = @_;
	if ( my $socket = new IO::Socket::UNIX (
		Peer     => $postfwd_settings{$type}{port},
		Timeout  => $postfwd_settings{timeout}{$type},
		Type     => SOCK_STREAM ) ) {
		$socket->print("$send\r\n");
		$send = $socket->getline();
		chomp($send);
		$socket->close();
	} else {
		warn("can not open socket to $postfwd_settings{$type}{host}:$postfwd_settings{$type}{port}: '$!' '$@'\n");
		undef $send;
	};
	return $send;
};

1; # EOF postfwd2::basic


############################
package postfwd2::cache;


## MODULES
use warnings;
use strict;
use base 'Net::Server::Multiplex';
import postfwd2::basic qw(:DEFAULT &wantsdebug &hash_to_list &str_to_hash &hash_to_str &ts $TIMEHIRES);
use vars qw( %Cache %Cleanup %Count %Interval %Top $Reload_Conf $Summary $StartTime );
# use Time::HiRes if available
BEGIN { Time::HiRes->import( qw(time) ) if $TIMEHIRES };


## SUBS

# prepare stats
sub list_stats {
	my @output = (); my $line = ''; my $now = time();
	my $uptime  = $now - $StartTime;
	return @output unless $uptime and (%Count or %Cache);
	push ( @output, sprintf (
		"[STATS] %s::cache %s: %d queries since %d days, %02d:%02d:%02d hours",
		$postfwd_settings{name},
		$postfwd_settings{version},
		$Count{cache_queries},
		($uptime / 60 / 60 / 24),
		(($uptime / 60 / 60) % 24),
		(($uptime / 60) % 60),
		($uptime % 60)
	) );
	my $lastreq = (($now - $Summary) > 0) ? (($Interval{request_set} || 0) + ($Interval{request_get} || 0)) / ($now - $Summary) * 60 : 0;
	$Top{request} = $lastreq if ($lastreq > ($Top{request} || 0)); $Top{request} ||= 0;
	my $lastdns = (($now - $Summary) > 0) ? (($Interval{dns_set} || 0) + ($Interval{dns_get} || 0)) / ($now - $Summary) * 60 : 0;
	$Top{dns} = $lastdns if ($lastdns > ($Top{dns} || 0)); $Top{dns} ||= 0;
	push ( @output, sprintf (
		"[STATS] Requests: %.1f/min last, %.1f/min overall, %.1f/min top",
		$lastreq,
		(($Count{request_set} || 0) + ($Count{request_get} || 0)) / $uptime * 60,
		$Top{request}
	) );
	push ( @output, sprintf (
		"[STATS] Dnsstats: %.1f/min last, %.1f/min overall, %.1f/min top",
		$lastdns,
		(($Count{dns_set} || 0) + ($Count{dns_get} || 0)) / $uptime * 60,
		$Top{dns}
	) ) unless ($postfwd_settings{dns}{disable} or $postfwd_settings{dns}{noparent});
	push ( @output, sprintf (
		"[STATS] Hitrates: %.1f%% requests, %.1f%% dns, %.1f%% rates",
		($Count{request_get}) ? ($Count{request_hits} || 0) / $Count{request_get} * 100 : 0,
		($Count{dns_get}) ? ($Count{dns_hits} || 0) / $Count{dns_get} * 100 : 0,
		($Count{rate_get}) ? ($Count{rate_hits} || 0) / $Count{rate_get} * 100 : 0
	) );
	push ( @output, "[STATS] Contents: ".
		join ', ', map { $_ = "$_=".(scalar keys %{$Cache{$_}}) } (reverse sort keys %Cache)
	);
	if (wantsdebug (qw[ all stats devel parent_cache ])) {
		push ( @output, "[STATS] Counters: ".
			join ', ', map { $_ = "$_=".$Count{$_} } (reverse sort keys %Count) );
		push ( @output, "[STATS] Interval: ".
			join ', ', map { $_ = "$_=".$Interval{$_} } (reverse sort keys %Interval) );
	};
	map { $Interval{$_} = 0 } (keys %Interval);
	$Summary = $now;
	return @output;
};

# return cache contents
sub dump_cache {
	my @result = ();
	foreach (keys %Cache) {
		push @result, hash_to_list ('%'.$_."_cache", %{$Cache{$_}}) if %{$Cache{$_}};
	}; return @result;
};

# get a whole cache item
sub get_cache {
	my ($self,$now,$type,$item) = @_;
	my @answer = ();
	return '<undef>' unless ( defined $Cache{$type}{$item}{'until'} and ($now <= $Cache{$type}{$item}{'until'}[0]));
	$Count{$type."_hits"}++;
	map { push @answer, "$_=".(join $postfwd_settings{seplst}, @{$Cache{$type}{$item}{$_}}) } (keys %{$Cache{$type}{$item}});
	return (join $postfwd_settings{sepreq}, @answer);
};

# set item to cache
sub set_cache {
	my ($self,$type,$item,$vals) = @_;
	my @answer = ();
	undef $Cache{$type}{$item};
	foreach my $arg (split ($postfwd_settings{sepreq}, $vals)) {
		map {	push @{$Cache{$type}{$item}{$1}}, $_;
			push @answer, "$type->$item->$1=$_";
			@{$Cache{$type}{$item}{$1}} = uniq(@{$Cache{$type}{$item}{$1}});
		} (split $postfwd_settings{seplst}, $2) if ($arg =~ m/$postfwd_patterns{keyval}/);
	};
	@answer = '<undef>' unless @answer;
	return (join '; ', @answer);
};

# get rate item
sub get_rate {
	my ($self,$now,$type,$item) = @_;
	my @answer = (); my $rindex = '';
	($item, $rindex) = split $postfwd_settings{seplim}, $item;
	return '<undef>' unless ( $item and $rindex and defined $Cache{$type}{$item} and defined $Cache{$type}{$item}{$rindex} and defined $Cache{$type}{$item}{$rindex}{'until'} and ($now <= $Cache{$type}{$item}{$rindex}{'until'}[0]));
	$Count{$type."_hits"}++;
	map { push @answer, "$_=".(join $postfwd_settings{seplst}, @{$Cache{$type}{$item}{$rindex}{$_}}) } (keys %{$Cache{$type}{$item}{$rindex}});
	return (join $postfwd_settings{sepreq}, @answer);
};

# set rate to cache
sub set_rate {
	my ($self,$now,$type,$item,$vals) = @_;
	my @answer = (); my $rindex = '';
	($item, $rindex) = split $postfwd_settings{seplim}, $item;
	return '<undef>' if ( defined $Cache{$type}{$item} and defined $Cache{$type}{$item}{$rindex} and defined $Cache{$type}{$item}{$rindex}{'until'} and $now <= @{$Cache{$type}{$item}{$rindex}{'until'}}[0] );
	push @{$Cache{$type}{$item}{'list'}}, $rindex;
	@{$Cache{$type}{$item}{'list'}} = uniq(@{$Cache{$type}{$item}{'list'}});
	delete $Cache{$type}{$item}{$rindex} if defined $Cache{$type}{$item}{$rindex};
	foreach my $arg (split ($postfwd_settings{sepreq}, $vals)) {
		map {	push @{$Cache{$type}{$item}{$rindex}{$1}}, $_;
			push @answer, "$type->$item->$rindex->$1=$_";
			@{$Cache{$type}{$item}{$rindex}{$1}} = uniq(@{$Cache{$type}{$item}{$rindex}{$1}});
		} (split $postfwd_settings{seplst}, $2) if ($arg =~ m/$postfwd_patterns{keyval}/);
	};
	@answer = '<undef>' unless @answer;
	return (join '; ', @answer);
};

# check rate limits
sub check_rate {
	my ($self,$now,$type,$item,$size,$rcpt) = @_;
	return '<undef>' unless ($type and $item);
	$size ||= 0; $rcpt ||= 0; my $answer = '';
	RATES: foreach my $arg (split ($postfwd_settings{seplst}, $item)) {
		next RATES unless (defined $Cache{$type}{$arg} and defined $Cache{$type}{$arg}{'list'});

		RINDEX: foreach my $rindex (@{$Cache{$type}{$arg}{'list'}}) {
			next RINDEX unless (defined $Cache{$type}{$arg}{$rindex} and defined $Cache{$type}{$arg}{$rindex}{'until'} and defined $Cache{$type}{$arg}{$rindex}{type});

			# renew rate
			if ( $now > @{$Cache{$type}{$arg}{$rindex}{'until'}}[0] ) {
				@{$Cache{$type}{$arg}{$rindex}{count}}[0] = ( (@{$Cache{$type}{$arg}{$rindex}{type}}[0] eq 'size') ? $size :
				  ((@{$Cache{$type}{$arg}{$rindex}{type}}[0] eq 'rcpt') ? $rcpt : 1 ) );
				@{$Cache{$type}{$arg}{$rindex}{'time'}}[0] = $now;
				@{$Cache{$type}{$arg}{$rindex}{'until'}}[0] = $now + @{$Cache{$type}{$arg}{$rindex}{ttl}}[0];
				log_info ("[RATES] renewing rate limit object '".$arg."'"
				  ." [type: ".@{$Cache{$type}{$arg}{$rindex}{type}}[0]
				  .", max: ".@{$Cache{$type}{$arg}{$rindex}{maxcount}}[0]
				  .", time: ".@{$Cache{$type}{$arg}{$rindex}{ttl}}[0]."s]")
				  if wantsdebug (qw[ all rates ]);
	
			# increase rate
			} else {
				@{$Cache{$type}{$arg}{$rindex}{count}}[0] += ( (@{$Cache{$type}{$arg}{$rindex}{type}}[0] eq 'size') ? $size :
				  ((@{$Cache{$type}{$arg}{$rindex}{type}}[0] eq 'rcpt') ? $rcpt : 1 ) );
				log_info ("[RATES] increasing rate limit object '".$arg."' to ".@{$Cache{$type}{$arg}{$rindex}{count}}[0]
				  ." [type: ".@{$Cache{$type}{$arg}{$rindex}{type}}[0]
				  .", max: ".@{$Cache{$type}{$arg}{$rindex}{maxcount}}[0]
				  .", time: ".@{$Cache{$type}{$arg}{$rindex}{ttl}}[0]."s]")
				  if wantsdebug (qw[ all rates ]);
			};
	
			# check rate
			if (not($answer) and @{$Cache{$type}{$arg}{$rindex}{count}}[0] > @{$Cache{$type}{$arg}{$rindex}{maxcount}}[0]) {
				$answer = $arg.$postfwd_settings{seplim}.$rindex.$postfwd_settings{seplst}.hash_to_str (%{$Cache{$type}{$arg}{$rindex}});
				$Count{$type."_hits"}++;
			};
		};
	};
	$answer = '<undef>' unless $answer;
	return $answer;
};

# clean up cache
sub cleanup_cache {
	my($type,$now) = @_;
	my $start = $Cleanup{$type} = time();
	log_info ("[CLEANUP] checking $type cache...") if wantsdebug (qw[ all cleanup parentcleanup ]);
	return unless defined $Cache{$type} and my $count = scalar keys %{$Cache{$type}};
	CLEANUP: foreach my $checkitem (keys %{$Cache{$type}}) {
		next CLEANUP unless (defined $Cache{$type}{$checkitem});
		unless ( defined $Cache{$type}{$checkitem}{'list'} ) {
			# remove incomplete objects
			if ( !defined($Cache{$type}{$checkitem}{'until'}) or !defined($Cache{$type}{$checkitem}{ttl}) ) {
				if ( wantsdebug (qw[ all cleanup parentcleanup devel ]) ) {
					log_info ("[CLEANUP] deleting incomplete $type cache item '$checkitem'");
					map { log_info ("[CLEANUP]  $_") } ( hash_to_list(%{$Cache{$type}{$checkitem}}) );
				};
				delete $Cache{$type}{$checkitem};
			# remove timed out objects
			} elsif ( $now > $Cache{$type}{$checkitem}{'until'}[0] ) {
				log_info ("[CLEANUP] removing $type cache item '$checkitem' after ttl ".$Cache{$type}{$checkitem}{ttl}[0]."s")
					if wantsdebug (qw[ all cleanup parentcleanup ]);
				delete $Cache{$type}{$checkitem};
			};
		} else {
			my @i = ();
			foreach my $crate (@{$Cache{$type}{$checkitem}{'list'}}) {
				if ( !(defined $Cache{$type}{$checkitem}{$crate}{'until'}) or !(defined $Cache{$type}{$checkitem}{$crate}{ttl}) ) {
					if ( wantsdebug (qw[ all cleanup parentcleanup devel ]) ) {
						log_info ("[CLEANUP] deleting incomplete $type cache item '$checkitem'->'$crate'");
						map { log_info ("[CLEANUP]  $_") } ( hash_to_list(%{$Cache{$type}{$checkitem}{$crate}}) );
					};
					delete $Cache{$type}{$checkitem}{$crate};
				} elsif ( $now > $Cache{$type}{$checkitem}{$crate}{'until'}[0] ) {
					log_info ("[CLEANUP] removing $type cache item '$checkitem'->'$crate' after ttl ".$Cache{$type}{$checkitem}{$crate}{ttl}[0]."s")
						if wantsdebug (qw[ all cleanup parentcleanup ]);
					delete $Cache{$type}{$checkitem}{$crate};
				} else {
					push @i, $crate;
				};
			};
			unless ($i[0]) {
				log_info ("[CLEANUP] removing $type cache complete item '$checkitem'")
					if wantsdebug (qw[ all cleanup parentcleanup ]);
				delete $Cache{$type}{$checkitem};
			} else {
				log_info ("[CLEANUP] new $type cache limits for item '$checkitem': ".(join ', ', @i))
					if wantsdebug (qw[ all cleanup parentcleanup ]);
				@{$Cache{$type}{$checkitem}{'list'}} = @i;
			};
		};
	};
	my $end = time();
	log_info ("[CLEANUP] cleaning $type cache needed ".ts($end - $start)." seconds for "
		.($count - scalar keys %{$Cache{$type}})." out of ".$count
		." cached items after cleanup time ".$postfwd_settings{$type}{cleanup}."s")
		if ( wantsdebug (qw[ all verbose cleanup parentcleanup ]) or (($end - $start) >= 1) );
};



## Net::Server::Multiplex methods

# ignore syslog failures
sub handle_syslog_error {};

# set $Reload_Conf marker on HUP signal
sub sig_hup {
	log_note ("catched HUP signal - clearing request cache on next request");
	$Reload_Conf = 1;
};

# cache start
sub pre_loop_hook() {
	my $self = shift;
	# change cache name
	$0 = $self->{server}->{commandline} = " ".$postfwd_settings{name}.'::cache';
	$self->{server}->{syslog_ident} = $postfwd_settings{name}."/cache";
	init_log ($self->{server}->{syslog_ident});
	$StartTime = $Summary = $Cleanup{request} = $Cleanup{rate} = $Cleanup{dns} = time();
	log_info ("ready for input");
};

# cache process request
sub mux_input {
	my ($self, $mux, $client, $mydata) = @_;
	my $action = '<undef>';
	my $now = time();
	while ( $$mydata =~ s/^([^\r\n]*)\r?\n// ) {
		# check request line
		next unless defined $1;
		my $request = $1;
		log_info ("request: '$request'") if wantsdebug (qw[ all ]);
		if ($Reload_Conf) {
			undef $Reload_Conf; my $s = ''; delete $Cache{request};
			unless ($postfwd_settings{keep_rates}) { delete $Cache{rate}; $s = 'and rate' }; 
			log_info ("request".(($s) ? " $s" : '')." cache cleared") if wantsdebug (qw[ all verbose ]);
		};
		if ($request eq $postfwd_patterns{ping}) {
			$action = $postfwd_patterns{pong};
		} elsif ($request =~ m/$postfwd_patterns{checkrate}/) {
			my ($type, $item, $size, $rcpt) = ($1, $2, $3, $4);
			log_info ("[CHECKRATE] request: '$request'") if wantsdebug (qw[ all rates cache getcache ]);
			cleanup_cache ($type,$now) if (($now - $Cleanup{$type}) > ($postfwd_settings{$type}{cleanup} || 300));
			$Count{cache_queries}++; $Interval{cache_queries}++;
			$Count{$type."_check"}++; $Interval{$type."_check"}++;
			$action = $self->check_rate($now,$type,$item,$size,$rcpt);
			log_info ("[CHECKRATE] answer: '$action'") if wantsdebug (qw[ all rates cache getcache ]);
		} elsif ($request =~ m/$postfwd_patterns{getcacheitem}/) {
			my ($type, $item) = ($1, $2);
			log_info ("[GETCACHEITEM] request: '$request'") if wantsdebug (qw[ all cache getcache ]);
			cleanup_cache ($type,$now) if (($now - $Cleanup{$type}) > ($postfwd_settings{$type}{cleanup} || 300));
			$Count{cache_queries}++; $Interval{cache_queries}++;
			$Count{$type."_get"}++; $Interval{$type."_get"}++;
			$action = $self->get_cache($now,$type,$item);
			log_info ("[GETCACHEITEM] answer: '$action'") if wantsdebug (qw[ all cache getcache ]);
		} elsif ($request =~ m/$postfwd_patterns{setcacheitem}/) {
			my ($type, $item, $vals) = ($1, $2, $3);
			log_info ("[SETCACHEITEM] request: '$request'") if wantsdebug (qw[ all cache setcache ]);
			$Count{cache_queries}++; $Interval{cache_queries}++;
			$Count{$type."_set"}++; $Interval{$type."_set"}++;
			$action = $self->set_cache($type,$item,$vals);
			log_info ("[SETCACHEITEM] answer: '$action'") if wantsdebug (qw[ all cache setcache ]);
		} elsif ($request =~ m/$postfwd_patterns{getrateitem}/) {
			my ($type, $item) = ($1, $2);
			log_info ("[GETRATEITEM] request: '$request'") if wantsdebug (qw[ all cache getcache rates ]);
			cleanup_cache ($type,$now) if (($now - $Cleanup{$type}) > ($postfwd_settings{$type}{cleanup} || 300));
			$Count{cache_queries}++; $Interval{cache_queries}++;
			$Count{$type."_get"}++; $Interval{$type."_get"}++;
			$action = $self->get_rate($now,$type,$item);
			log_info ("[GETRATEITEM] answer: '$action'") if wantsdebug (qw[ all cache getcache rates ]);
		} elsif ($request =~ m/$postfwd_patterns{setrateitem}/) {
			my ($type, $item, $vals) = ($1, $2, $3);
			log_info ("[SETRATEITEM] request: '$request'") if wantsdebug (qw[ all cache setcache ]);
			$Count{cache_queries}++; $Interval{cache_queries}++;
			$Count{$type."_set"}++; $Interval{$type."_set"}++;
			$action = $self->set_rate($now,$type,$item,$vals);
			log_info ("[SETRATEITEM] answer: '$action'") if wantsdebug (qw[ all cache setcache ]);
		} elsif ($request =~ m/$postfwd_patterns{dumpstats}/) {
			$action = join $postfwd_settings{sepreq}.$postfwd_settings{seplst}, list_stats();
		} elsif ($request =~ m/$postfwd_patterns{dumpcache}/) {
			$action = join $postfwd_settings{sepreq}.$postfwd_settings{seplst}, dump_cache();
		} else {
			log_note ("warning: ignoring unknown command '".substr($request,0,512)."'");
		};
		print $client "$action\n";
		log_info ("answer: '$action'") if wantsdebug (qw[ all ]);
	};
};

1; # EOF postfwd2::cache


############################
package postfwd2::server;

use warnings;
use strict;
use IO::Socket qw(SOCK_STREAM);
use Net::DNS;
use base 'Net::Server::PreFork';
import postfwd2::basic qw(:DEFAULT %postfwd_commands &check_inet &check_unix &wantsdebug &hash_to_str &str_to_hash &hash_to_list &ts $TIMEHIRES);
# export these functions for '-C' switch
use Exporter qw(import);
our @EXPORT_OK = qw(
	&read_config &show_config &process_input &get_plugins
);
# use Time::HiRes if available
BEGIN { Time::HiRes->import( qw(time) ) if $TIMEHIRES };


# these items have to be compared as...
# scoring
my $COMP_SCORES               = "score";
my $COMP_NS_NAME              = "sender_ns_names";
my $COMP_NS_ADDR              = "sender_ns_addrs";
my $COMP_MX_NAME              = "sender_mx_names";
my $COMP_MX_ADDR              = "sender_mx_addrs";
my $COMP_HELO_ADDR            = "helo_address";
# networks in CIDR notation (a.b.c.d/nn)
my $COMP_NETWORK_CIDRS        = "(client_address|sender_(ns|mx)_addrs|helo_address)";
# RBL checks
my $COMP_DNSBL_TEXT           = "dnsbltext";
my $COMP_RBL_CNT              = "rblcount";
my $COMP_RHSBL_CNT            = "rhsblcount";
my $COMP_RBL_KEY              = "rbl";
my $COMP_RHSBL_KEY            = "rhsbl";
my $COMP_RHSBL_KEY_CLIENT     = "rhsbl_client";
my $COMP_RHSBL_KEY_SENDER     = "rhsbl_sender";
my $COMP_RHSBL_KEY_RCLIENT    = "rhsbl_reverse_client";
my $COMP_RHSBL_KEY_HELO       = "rhsbl_helo";
my %DNSBLITEMS = (
	rbl => {
		cnt	=> "rblcount",
	},
	rhsbl => {
		cnt	=> "rhsblcount",
	},
	rhsbl_client => {
		cnt	=> "rhsblcount",
	},
	rhsbl_sender => {
		cnt	=> "rhsblcount",
	},
	rhsbl_reverse_client => {
		cnt	=> "rhsblcount",
	},
	rhsbl_helo => {
		cnt	=> "rhsblcount",
	},
);
# dns key value matching
my %DNS_REPNAMES = (
	"NS"	=> "nsdname",
	"MX"	=> "exchange",
	"A"	=> "address",
	"TXT"	=> "char_str_list",
	"CNAME"	=> "cname",
);

# file items
our($COMP_CONF_FILE)            = 'cfile|file';
our($COMP_CONF_TABLE)           = 'ctable|table';
our($COMP_LIVE_FILE)            = 'lfile';
our($COMP_LIVE_TABLE)           = 'ltable';
our($COMP_TABLES)               = qr/^($COMP_CONF_TABLE|$COMP_LIVE_TABLE)$/i;
our($COMP_CONF_FILE_TABLE)      = qr/^($COMP_CONF_FILE|$COMP_CONF_TABLE):(.+)$/i;
our($COMP_LIVE_FILE_TABLE)      = qr/^($COMP_LIVE_FILE|$COMP_LIVE_TABLE):(.+)$/i;
# date checks
my $COMP_DATE                 = "date";
my $COMP_TIME                 = "time";
my $COMP_DAYS                 = "days";
my $COMP_MONTHS               = "months";
# always true
my $COMP_ACTION               = "action";
my $COMP_ID                   = "id";
my $COMP_CACHE                = "cache";
# rule hits
my $COMP_HITS                 = "request_hits";
# item match counter
my $COMP_MATCHES              = "matches";
# separator
my $COMP_SEPARATOR            = "[=\~\<\>]=|[=\!][=\~\<\>]|=";
# macros
my $COMP_ACL                  = "[\&][\&]";
# negation
my $COMP_NEG                  = "[\!][\!]";
# variables
my $COMP_VAR                  = "[\$][\$]";
# date calculations
my $COMP_DATECALC             = "($COMP_DATE|$COMP_TIME|$COMP_DAYS|$COMP_MONTHS)";
# these items allow whitespace-or-comma-separated values
my $COMP_CSV                  = "($COMP_NETWORK_CIDRS|$COMP_RBL_KEY|$COMP_RHSBL_KEY|$COMP_RHSBL_KEY_CLIENT|$COMP_RHSBL_KEY_HELO|$COMP_RHSBL_KEY_SENDER|$COMP_RHSBL_KEY_RCLIENT|$COMP_DATECALC|$COMP_HELO_ADDR|$COMP_NS_ADDR|$COMP_MX_ADDR)";
# dont treat these as lists
my $COMP_SINGLE               = "($COMP_ID|$COMP_ACTION|$COMP_CACHE|$COMP_SCORES|$COMP_RBL_CNT|$COMP_RHSBL_CNT)";

# date tools
my %months = (
	"Jan" =>  0, "jan" =>  0, "JAN" =>  0,
	"Feb" =>  1, "feb" =>  1, "FEB" =>  1,
	"Mar" =>  2, "mar" =>  2, "MAR" =>  2,
	"Apr" =>  3, "apr" =>  3, "APR" =>  3,
	"May" =>  4, "may" =>  4, "MAY" =>  4,
	"Jun" =>  5, "jun" =>  5, "JUN" =>  5,
	"Jul" =>  6, "jul" =>  6, "JUL" =>  6,
	"Aug" =>  7, "aug" =>  7, "AUG" =>  7,
	"Sep" =>  8, "sep" =>  8, "SEP" =>  8,
	"Oct" =>  9, "oct" =>  9, "OCT" =>  9,
	"Nov" => 10, "nov" => 10, "NOV" => 10,
	"Dec" => 11, "dec" => 11, "DEC" => 11,
);
my %weekdays = (
	"Sun" => 0, "sun" => 0, "SUN" => 0,
	"Mon" => 1, "mon" => 1, "MON" => 1,
	"Tue" => 2, "tue" => 2, "TUE" => 2,
	"Wed" => 3, "wed" => 3, "WED" => 3,
	"Thu" => 4, "thu" => 4, "THU" => 4,
	"Fri" => 5, "fri" => 5, "FRI" => 5,
	"Sat" => 6, "sat" => 6, "SAT" => 6,
);

use vars qw(
	@Rules @DNSBL_Text @Rate_Items
	%Rule_by_ID %Matches %ACLs %Timeouts %Hits %Count
	%postfwd_items %postfwd_compare %postfwd_actions
	%postfwd_items_plugin %postfwd_compare_plugin %postfwd_actions_plugin
	%Request_Cache %Config_Cache %DNS_Cache %Rate_Cache
	$Cleanup_Requests $Cleanup_RBLs $Cleanup_Rates $Cleanup_Timeouts
	%Cache %Cleanup $StartTime $Summary
);


## SUBS

# cache query
sub cache_query { return ( &{$postfwd_settings{cache}{check}}('cache',@_) || '<undef>' ) };

# get ip and mask
sub cidr_parse {
	return undef unless defined $_[0];
	return undef unless $_[0] =~ m/^(\d+)\.(\d+)\.(\d+)\.(\d+)\/(\d+)$/;
	return undef unless ($1 < 256 and $2 < 256 and $3 < 256 and $4 < 256 and $5 <= 32 and $5 >= 0);
	my $net = ($1<<24)+($2<<16)+($3<<8)+$4;
	my $mask = ~((1<<(32-$5))-1);
	return ($net & $mask, $mask);
};

# compare address to network
sub cidr_match {
	my ($net, $mask, $addr) = @_;
	return undef unless defined $net and defined $addr;
	$addr =  ($1<<24)+($2<<16)+($3<<8)+$4 if ($addr =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/);
	return ($addr & $mask) == $net;
};

# sets an action for a score
sub modify_score {
	my($myscore,$myaction) = @_;
	log_info ( ((defined $postfwd_settings{scores}{$myscore}) ? "redefined" : "setting new")
		." score $myscore with action=\"$myaction\"") if wantsdebug (qw[ all verbose ]);
	$postfwd_settings{scores}{$myscore} = $myaction;
};

# returns content of !!() negation
sub deneg_item {
	my($val) = (defined $_[0]) ? $_[0] : '';
	return ( ($val =~ /^$COMP_NEG\s*\(?\s*(.+?)\s*\)?$/) ? $1 : '' );
};

# resolves $$() variables
sub devar_item {
	my($cmp,$val,$myitem,%request) = @_;
	return '' unless $val and $myitem;
	my($pre,$post,$var,$myresult) = '';
	while ( ($val =~ /(.*)$COMP_VAR\s*(\w+)(.*)/g) or ($val =~ /(.*)$COMP_VAR\s*\((\w+)\)(.*)/g) ) {
		($pre,$var,$post) = ($1,$2,$3);
		if ($var eq $COMP_DNSBL_TEXT) {
			$myresult=$val=$pre.(join "; ", uniq(@DNSBL_Text)).$post;
		} elsif (defined $request{$var}) {
			$myresult=$val=$pre.$request{$var}.$post;
		};
		log_info ("substitute :  \"$myitem\"  \"$cmp\"  \"$val\"") if wantsdebug (qw[ all verbose ]);
	};
	return $myresult;
};

# clean up RBL cache
sub cleanup_dns_cache {
	my($now) = $_[0]; return unless $now;
	foreach my $checkitem (keys %DNS_Cache) {
		# remove inclomplete objects (dns timeouts)
		if ( !defined($DNS_Cache{$checkitem}{'until'}) or !defined($DNS_Cache{$checkitem}{ttl}) ) {
			log_info ("[CLEANUP] deleting incomplete dns-cache item '$checkitem'")
				if wantsdebug (qw[ all cleanup childcleanup devel ]);
			delete $DNS_Cache{$checkitem};
		# remove timed out objects
		} elsif ( $now > $DNS_Cache{$checkitem}{'until'} ) {
			log_info ("[CLEANUP] removing dns-cache item '$checkitem' after ttl ".$DNS_Cache{$checkitem}{ttl}."s")
				if wantsdebug (qw[ all cleanup childcleanup ]);
			delete $DNS_Cache{$checkitem};
		};
	};
};

# clean up request cache
sub cleanup_request_cache {
	my($now) = $_[0]; return unless $now;
	RITEM: foreach my $checkitem (keys %Request_Cache) {
		next RITEM unless defined $Request_Cache{$checkitem}{'until'};
		if ( !defined($Request_Cache{$checkitem}{'until'}) or !defined($Request_Cache{$checkitem}{ttl}) ) {
			log_info ("[CLEANUP] deleting incomplete request-cache item '$checkitem'")
				if wantsdebug (qw[ all cleanup childcleanup devel ]);
			delete $Request_Cache{$checkitem};
		} elsif ( $now > $Request_Cache{$checkitem}{'until'} ) {
			log_info ("[CLEANUP] removing request-cache item '$checkitem' after ttl ".$Request_Cache{$checkitem}{ttl}."s")
				if wantsdebug (qw[ all cleanup childcleanup ]);
			delete $Request_Cache{$checkitem};
		};
	};
};

# clean up rate cache
sub cleanup_rate_cache {
	my($now) = $_[0]; return unless $now;
	foreach my $checkitem (keys %Rate_Cache) {
		unless (defined $Rate_Cache{$checkitem}{'list'}) {
			log_info ("[CLEANUP] deleting incomplete rate-cache item '$checkitem'")
				if wantsdebug (qw[ all cleanup childcleanup devel ]);
			delete $Rate_Cache{$checkitem};
		} else {
			my @i = ();
			foreach my $crate (@{$Rate_Cache{$checkitem}{'list'}}) {
				if ( not(defined $Rate_Cache{$checkitem}{$crate}{'until'}) or not(defined $Rate_Cache{$checkitem}{$crate}{'ttl'}) ) {
					log_info ("[CLEANUP] deleting incomplete rate-cache item '$checkitem'->'$crate'")
						if wantsdebug (qw[ all cleanup childcleanup devel ]);
					delete $Rate_Cache{$checkitem}{$crate};
				} elsif ( $now > $Rate_Cache{$checkitem}{$crate}{'until'} ) {
					log_info ("[CLEANUP] removing rate-cache item '$checkitem'->'$crate' after ttl ".$Rate_Cache{$checkitem}{$crate}{ttl}."s")
						if wantsdebug (qw[ all cleanup childcleanup ]);
					delete $Rate_Cache{$checkitem}{$crate};
				} else {
					push @i, $crate;
				};
			};
			unless ($i[0]) {
				log_info ("[CLEANUP] removing complete rate-cache item '$checkitem'")
					if wantsdebug (qw[ all cleanup childcleanup ]);
				delete $Rate_Cache{$checkitem};
			} else {
				log_info ("[CLEANUP] new limits for rate-cache item '$checkitem': ".(join ', ', @i))
					if wantsdebug (qw[ all cleanup childcleanup ]);
				@{$Rate_Cache{$checkitem}{'list'}} = @i;
			};
		};
	};
};

# preparses configuration line for ACL syntax
sub acl_parser {
	my($file,$num,$myline) = @_;
	if ( $myline =~ /^\s*($COMP_ACL[\-\w]+)\s*{\s*(.*?)\s*;?\s*}[\s;]*$/ ) {
		$ACLs{$1} = $2; $myline = "";
	} else {
		while ( $myline =~ /($COMP_ACL[\-\w]+)/) {
			my($acl)  = $1;
			if ( $acl and defined $ACLs{$acl} ) {
				$myline =~ s/\s*$acl\s*/$ACLs{$acl}/g;
			} else {
				#return "action=note(undefined macro '$acl')";
				log_warn ("file $file, ignoring line $num: undefined macro '$acl'");
				return "";
			};
		};
	};
	return $myline;
};

# prepares pcre item
sub prepare_pcre {
	my($item) = shift; undef my $neg;
	# temporarily remove negation
	$item = $neg if ($neg = deneg_item($item));
	# allow // regex
	$item =~ s/^\/?(.*?)\/?$/$1/;
	# tested slow
	#$item = qr/$item/i;
	# re-enable negation
	$item = "!!($item)" if $neg;
	return $item;
};

# prepares file item
sub prepare_file {
	my($forced_reload,$type,$cmp,$file) = @_; my(@result) = (); undef my $fh;
	my($is_table) = ($type =~ /^$COMP_TABLES$/);
	unless (-e $file) {
		log_warn ("error: $type:$file not found - will be ignored");
		return @result;
	};
	if ( not($forced_reload) and (defined $Config_Cache{$file}{lastread}) and ($Config_Cache{$file}{lastread} > (stat $file)[9]) ) {
		log_info ("$type:$file unchanged - using cached content (mtime: "
				.(stat $file)[9].", cache: $Config_Cache{$file}{lastread})")
				if wantsdebug (qw[ all config ]);
		return  @{$Config_Cache{$file}{content}};
	};
	unless (open ($fh, "<$file")) {
		log_warn ("error: could not open $type:$file - $! - will be ignored");
		return @result;
	};
	log_info ("reading $type:$file") if wantsdebug (qw[ all config ]);
	while (<$fh>) {
		chomp;
		s/#.*//g;
		next if /^\s*$/;
		s/\s+[^\s]+$// if $is_table;
		s/^\s+//; s/\s+$//;
		push @result, prepare_item($forced_reload, $cmp, $_);
	}; close ($fh);
        # update Config_Cache
        $Config_Cache{$file}{lastread}   = time();
        @{$Config_Cache{$file}{content}} = @result;
	log_info ("read ".($#result + 1)." items from $type:$file") if wantsdebug (qw[ all config ]);
	return @result;
};

# prepares ruleset item
sub prepare_item {
	my($forced_reload,$cmp,$item) = @_; my(@result) = (); undef my $type;
	if ($item =~ /$COMP_CONF_FILE_TABLE/) {
		return prepare_file ($forced_reload, $1, $cmp, $2);
	} elsif ($cmp eq '=~' or $cmp eq '!~') {
		return $cmp.";".prepare_pcre($item);
	} else {
		return $cmp.";".$item;
	};
};

# compatibility for old "rate"-syntax
sub check_for_old_syntax {
  my($myindex,$myfile,$mynum,$mykey,$myvalue) = @_;
  if ($mykey =~ /^action$/) {
    if ($myvalue =~ /^(\w[\-\w]+)\s*\(\s*(.*?)\s*\)$/) {
	my($mycmd,$myarg) = ($1, $2);
	if ($mycmd =~ /^(rate|size|rcpt)$/i) {
	  if ($myarg =~ /^\$\$(.*)$/) {
	    $myarg = $1;
	    $myvalue = "$mycmd($myarg)";
	    log_note ( "notice: Rule $myindex ($myfile line $mynum): "
	    ."removing obsolete '\$\$' for $mycmd limit index. See man page for new syntax." ) if wantsdebug (qw[ all config verbose ]);
	  };
	  push @Rate_Items, (split '/', $myarg)[0];
	};
    };
  };
  return $myvalue;
};

# parses configuration line
sub parse_config_line {
	my($forced_reload, $myfile, $mynum, $myindex, $myline) = @_;
	my(%myrule) = ();
	my($mykey, $myvalue, $mycomp);
	eval {
	    local $SIG{'__DIE__'};
	    local $SIG{'ALRM'}  = sub { $myline =~ s/[ \t][ \t]*/ /g; log_warn ("timeout after ".$postfwd_settings{timeout}{config}."s at parsing Rule $myindex ($myfile line $mynum): \"$myline\""); %myrule = (); die };
	    my $prevalert = alarm($postfwd_settings{timeout}{config}) if $postfwd_settings{timeout}{config};
	    if ( $myline = acl_parser ($myfile, $mynum, $myline) ) {
		unless ( $myline =~ /^\s*[^=\s]+\s*$COMP_SEPARATOR\s*([^;\s]+\s*)+(;\s*[^=\s]+\s*$COMP_SEPARATOR\s*([^;\s]+\s*)+)*[;\s]*$/ ) {
			log_warn ("ignoring invalid $myfile line ".$mynum.": \"".$myline."\"");
		} else {
			# separate items
			foreach (split ";", $myline) {
				# remove whitespaces around
				s/^\s*(.*?)\s*($COMP_SEPARATOR)\s*(.*?)\s*$/$1$2$3/;
				( ($mycomp = $2) =~ /^([\<\>\~])=$/ ) and $mycomp = "=$1";
				($mykey, $myvalue) = split /$COMP_SEPARATOR/, $_, 2;
				if ($mykey =~ /^$COMP_SINGLE$/) {
					log_note ( "notice: Rule $myindex ($myfile line $mynum):"
						." overriding $mykey=\"".$myrule{$mykey}."\""
						." with $mykey=\"$myvalue\""
						) if (defined $myrule{$mykey});
					$myvalue = check_for_old_syntax($myindex,$myfile,$mynum,$mykey,$myvalue);
					$myrule{$mykey} = $myvalue;
				} elsif ($mykey =~ /^$COMP_CSV$/) {
					map { push @{$myrule{$mykey}}, prepare_item ($forced_reload, $mycomp, $_) } ( split /\s*,\s*/, $myvalue );
				} else {
					push @{$myrule{$mykey}}, prepare_item ($forced_reload, $mycomp, $myvalue);
				};
			};
			unless (exists($myrule{$COMP_ACTION})) {
				log_warn ("Rule ".$myindex." ($myfile line ".$mynum."): contains no action and will be ignored");
				return (%myrule = ());
			};
			unless (exists($myrule{$COMP_ID})) {
				$myrule{$COMP_ID} = "R-".$myindex;
				log_note ("notice: Rule $myindex ($myfile line $mynum): contains no rule identifier - will use \"$myrule{id}\"") if wantsdebug (qw[ all config verbose ]);
			};
			log_info ("loaded: Rule $myindex ($myfile line $mynum): id->\"$myrule{id}\" action->\"$myrule{action}\"") if wantsdebug (qw[ all config verbose ]);
		};
	    };
	    alarm($prevalert) if $postfwd_settings{timeout}{config};
	};
	return %myrule;
};

# parses configuration file
sub read_config_file {
	my($forced_reload, $myindex, $myfile) = @_;
	my(%myrule, @myruleset, @lines) = ();
	my($mybuffer) = ""; undef my $fh;

	unless (-e $myfile) {
		log_warn ("error: file ".$myfile." not found - file will be ignored");
	} else {
		unless (open ($fh, "<$myfile")) {
			log_warn ("error: could not open ".$myfile." - $! - file will be ignored");
		} else {
			log_info ("reading file $myfile") if wantsdebug (qw[ all config verbose ]);
			while (<$fh>) {
				chomp;
				s/(\"|#.*)//g;
				next if /^\s*$/;
				if ( /(.*)\\\s*$/ or /(.*\{)\s*$/ ) { $mybuffer = $mybuffer.$1; next; };
				$mybuffer .= $_;
				if ( $lines[0] and $mybuffer =~ /^(\}|\s+\S)/ ) {
					my $last = pop(@lines); $last .= ';' unless $last =~ /;\s*$/;
					$mybuffer = $last.$mybuffer;
				};
				push @lines, $mybuffer;
				$mybuffer = "";
			};
			map {
				log_info ("parsing line: '$_'") if wantsdebug (qw[ all config ]);
				%myrule = parse_config_line ($forced_reload, $myfile, $., ($#myruleset+$myindex+1), $mybuffer.$_);
				push ( @myruleset, { %myrule } ) if (%myrule);
				$mybuffer = "";
			} @lines;
			close ($fh);
			log_info ("loaded: Rules $myindex - ".($myindex + $#myruleset)." from file \"$myfile\"") if wantsdebug (qw[ all config verbose ]);
		};
	};
	return @myruleset;
};

# reads all configuration items
sub read_config {
	my($forced_reload) = shift;
	my(%myrule, @myruleset) = ();
	my($mytype,$myitem,$config);

	# init, cleanup cache and config vars
	@Rules = (); %Rule_by_ID = %Request_Cache = (); @Rate_Items = ();
	%Rate_Cache = () unless $postfwd_settings{keep_rates};

	# parse configurations
	for $config (@{$postfwd_settings{Configs}}) {
		($mytype,$myitem) = split $postfwd_settings{sepreq}, $config;
		if ($mytype eq "r" or $mytype eq "rule") {
			%myrule = parse_config_line ($forced_reload, 'RULE', 0, ($#Rules + 1), $myitem);
			push ( @Rules, { %myrule } ) if (%myrule);
		} elsif ($mytype eq "f" or $mytype eq "file") {
			if ( not($forced_reload) and defined $Config_Cache{$myitem}{lastread} and ($Config_Cache{$myitem}{lastread} > (stat $myitem)[9]) ) {
				log_info ("file \"$myitem\" unchanged - using cached ruleset (mtime: ".(stat $myitem)[9].",
					cache: $Config_Cache{$myitem}{lastread})"
					) if wantsdebug (qw[ all config verbose ]);
				push ( @Rules, @{$Config_Cache{$myitem}{ruleset}} ) if $Config_Cache{$myitem}{ruleset};
			} else {
				@myruleset = read_config_file ($forced_reload, ($#Rules + 1), $myitem);
				if (@myruleset) {
					@Rules = ( @Rules, @myruleset ) if @myruleset;
					$Config_Cache{$myitem}{lastread} = time();
					@{$Config_Cache{$myitem}{ruleset}} = @myruleset;
				};
			};
		};
	};
	if ($#Rules < 0) {
		log_warn("critical: no rules found - i feel useless (have you set -f or -r?)");
	} else {
		# update Rule by ID hash
		map { $Rule_by_ID{$Rules[$_]{$COMP_ID}} = $_ } (0 .. $#Rules);
		if ( @Rate_Items ) {
			@Rate_Items = uniq(@Rate_Items);
			log_info ("rate items: ".(join ', ', @Rate_Items)) if wantsdebug (qw[ all verbose rates ]);
		};
	};
};

# displays configuration
sub show_config {
	if (wantsdebug (qw[ all verbose ])) {
		print STDOUT "=" x 75, "\n";
		printf STDOUT "Rule count: %s\n", ($#Rules + 1);
		print STDOUT "=" x 75, "\n";
	};
	for my $index (0 .. $#Rules) {
		next unless exists $Rules[$index];
		printf STDOUT "Rule %3d: id->\"%s\"; action->\"%s\"", $index, $Rules[$index]{$COMP_ID}, $Rules[$index]{$COMP_ACTION};
		my $line = (wantsdebug (qw[ all verbose ])) ? "\n\t  " : "";
		for my $mykey ( reverse sort keys %{$Rules[$index]} ) {
			unless (($mykey eq $COMP_ACTION) or ($mykey eq $COMP_ID)) {
				$line .= "; " unless wantsdebug (qw[ all verbose ]);
				$line .= ($mykey =~ /^$COMP_SINGLE$/)
					? $mykey."->\"".$Rules[$index]{$mykey}."\""
					: $mykey."->\"".(join ', ', @{$Rules[$index]{$mykey}})."\"";
				$line .= " ; " if wantsdebug (qw[ all verbose ]);
			};
		};
		$line =~ s/\s*\;\s*$// if wantsdebug (qw[ all verbose ]);
		printf STDOUT "%s\n", $line;
		print STDOUT "-" x 75, "\n" if wantsdebug (qw[ all verbose ]);
	};
};


## sub DNS

# checks for rbl timeouts
sub rbl_timeout {
    my($myrbl) = shift;
    return ( ($postfwd_settings{dns}{max_timeout} > 0) and (defined $Timeouts{$myrbl}) and ($Timeouts{$myrbl} > $postfwd_settings{dns}{max_timeout}) );
};

# reads DNS answers
sub rbl_read_dns {
    my($myresult)		= shift;
    my($now)			= time();
    my($que,$ttl,$res,$typ)	= undef;
    my(@addrs,@texts)		= ();

    if ( defined $myresult ) {
	# read question, for dns cache id
	foreach ($myresult->question) {
		$typ = ($_->qtype || ''); $que = ($_->qname || '');
		map { &{$postfwd_settings{syslog}{logger}} ('info', "[GETDNS00] type=$typ, query=$que, $_") } (hash_to_list ('%packet', %{$myresult}))
			if wantsdebug (qw[ all dns getdns getdnspacket ]);
		next unless ($typ and $que);
		log_info ("[GETDNS01] type=$typ, query=$que") if wantsdebug (qw[ all dns getdns ]);
		unless ( (defined $DNS_Cache{$que})
			and (($typ eq 'A') or ($typ eq 'TXT')) ) {
			log_note ("[DNSBL] ignoring unknown query '$que', type '$typ'");
			next;
		};

		# parse answers
		foreach ($myresult->answer) {
			log_info ("[GETDNS02] type=$typ, query=$que, restype='".$_->type."'") if wantsdebug (qw[ all dns getdns ]);
			if ($_->type eq 'A') {
				push @addrs, $_->address if $_->address;
				$ttl = $_->ttl;
				log_info ("[GETDNSA1] type=$typ, query=$que, ttl=$ttl, answer='".($_->address || '')."'") if wantsdebug (qw[ all dns getdns ]);
			} elsif ($_->type eq 'TXT') {
				$res = (join(" ", $_->char_str_list()) || '');
				# escape commas for set() action
				$res =~ s/,/ /g;
				push @texts, $res;
				$ttl = $_->ttl;
				log_info ("[GETDNST1] type=$typ, query=$que, ttl=$ttl, answer='$res'") if wantsdebug (qw[ all dns getdns ]);
			} elsif (wantsdebug (qw[ all dns getdns ])) {
				log_info ("[GETDNS??] received answer type=".$typ." for query $que");
			};
		};

		# save result in cache
		if ($typ eq 'A') {
			$ttl = ( $DNS_Cache{$que}{ttl} > ($ttl||=0) ) ? $DNS_Cache{$que}{ttl} : $ttl;
			@{$DNS_Cache{$que}{A}}	  = @addrs;
			$DNS_Cache{$que}{ttl}	  = $ttl;
			$DNS_Cache{$que}{delay}   = ($now - $DNS_Cache{$que}{delay});
			$DNS_Cache{$que}{'log'}	  = 1;
			$DNS_Cache{$que}{'until'} = $now + $DNS_Cache{$que}{ttl};
			log_info ("[GETDNSA2] type=$typ, query=$que, cache='".(hash_to_str(%{$DNS_Cache{$que}}))."'") if wantsdebug (qw[ all dns getdns ]);
		#} elsif ($typ eq 'TXT') {
		} else {
			$res = (join(" ", @texts) || '');
			$ttl = ( $DNS_Cache{$que}{ttl} > ($ttl||=0) ) ? $DNS_Cache{$que}{ttl} : $ttl;
			$DNS_Cache{$que}{TXT} = $res;
			$DNS_Cache{$que}{ttl}  = $ttl unless $DNS_Cache{$que}{ttl};
			log_info ("[GETDNST2] type=$typ, query=$que, cache='".(hash_to_str(%{$DNS_Cache{$que}}))."'") if wantsdebug (qw[ all dns getdns ]);
		};
	};
	return $que if (@addrs || $res);
    } else {
	log_note ("[DNSBL] dns timeout");
    };
};

# fires DNS queries
sub rbl_prepare_lookups {
    my($mytype, $myval, @myrbls) = @_;
    my($myresult) = undef;
    my($cmp,$rblitem,$myquery);
    my(@lookups) = ();

    # skip these
    return @lookups if (($myval eq '') or ($myval eq "unknown")) or ($myval =~ /:/);

    # removes duplicate lookups, but keeps the specified order
    @myrbls = uniq(@myrbls);

    RBLQUERY: foreach (@myrbls) {

	# separate rbl-name and answer
	($cmp,$rblitem) = split ";", $_;
	next RBLQUERY unless $rblitem;
	my($myrbl, $myrblans, $myrbltime) = split /\//, $rblitem;
	next RBLQUERY unless $myrbl;
	next RBLQUERY if rbl_timeout($myrbl);
	$myrblans = $postfwd_settings{dns}{mask} unless $myrblans;
	$myrbltime = $postfwd_settings{dns}{ttl} unless $myrbltime;

	# create query string
	$myquery = $myval.".".$myrbl;
	my $mypat = qr/$myrblans/;

	# query our cache
	if ( exists($DNS_Cache{$myquery}) and exists($DNS_Cache{$myquery}{A}) ) {
		ANSWER1: foreach (@{$DNS_Cache{$myquery}{A}}) { last ANSWER1 if $myresult = ( $_ =~ /$mypat/ ) };
		log_info ("[DNSBL] cached $mytype: $myrbl $myval ($myquery) - answer: \'".(join ", ", @{$DNS_Cache{$myquery}{A}})."\'")
			if ( wantsdebug (qw[ all ]) or ($myresult and wantsdebug (qw[ verbose ])) );

	# query parent cache
	} elsif (   not($postfwd_settings{dns}{noparent})
		and not((my $pans = cache_query ("CMD=".$postfwd_commands{getcacheitem}.";TYPE=dns;ITEM=$myquery")) eq '<undef>') ) {
		%{$DNS_Cache{$myquery}} = str_to_hash($pans); delete $DNS_Cache{$myquery}{'log'} if $DNS_Cache{$myquery}{'log'};
		if ($DNS_Cache{$myquery}{A}) {
			ref $DNS_Cache{$myquery}{A} eq 'ARRAY' or $DNS_Cache{$myquery}{A} = [ $DNS_Cache{$myquery}{A} ];
			ANSWER2: foreach (@{$DNS_Cache{$myquery}{A}}) { last ANSWER2 if $myresult = ( $_ =~ /$mypat/ ) };
			log_info ("[DNSBL] parent cached $mytype: $myrbl $myval ($myquery) - answer: \'".(join ", ", @{$DNS_Cache{$myquery}{A}})."\'")
				if ( wantsdebug (qw[ all ]) or ($myresult and wantsdebug (qw[ verbose ])) );
		};

	# not found -> prepare dns query
	} else {
		$DNS_Cache{$myquery} = {
			type		=> $mytype,
			name		=> $myrbl,
			value		=> $myval,
			ttl		=> $myrbltime,
			delay		=> time(),
		};
		log_info("[DNSBL] query $mytype:  $myrbl $myval ($myquery)") if wantsdebug (qw[ all ]);
		push @lookups, $myquery;
	};
    };
    # return necessary lookups
    return @lookups;
};

# checks RBL items
sub rbl_check {
    my($mytype,$myrbl,$myval) = @_;
    my($myanswer,$myrblans,$myrbltime,$myresult,$mystart,$myend);
    my($m1,$m2,$myrbltype,$m4,$myrbltxt,$myquery);
    my($now) = time();

    # skip these
    return $myresult if (($myval eq '') or ($myval eq "unknown")) or ($myval =~ /:/);

    # separate rbl-name and answer
    ($myrbl, $myrblans, $myrbltime) = split '/', $myrbl; 
    $myrblans = $postfwd_settings{dns}{mask} unless $myrblans;
    $myrbltime = $postfwd_settings{dns}{ttl} unless $myrbltime;

    # create query string
    $myquery = $myval.".".$myrbl;

    # query our cache
    return $myresult unless ( $myresult = (defined $DNS_Cache{$myquery} and not(defined $DNS_Cache{$myquery}{'timed'})) );
    if (not($postfwd_settings{dns}{noparent}) and defined $DNS_Cache{$myquery}{'log'}) {
	my $pdns = "CMD=".$postfwd_commands{setcacheitem}.";TYPE=dns;ITEM=$myquery".hash_to_str(%{$DNS_Cache{$myquery}});
	cache_query ($pdns);
    };
    if ( $myresult  = ($#{$DNS_Cache{$myquery}{A}} >= 0) ) {
	my $mypat = qr/$myrblans/;
	ANSWER: foreach (@{$DNS_Cache{$myquery}{A}}) {
		last ANSWER if ( $myresult = ( ($_) and ($_ =~ m/$mypat/)) );
	};
	push @DNSBL_Text, $DNS_Cache{$myquery}{type}.':'.$DNS_Cache{$myquery}{name}.':<'.($DNS_Cache{$myquery}{TXT} || '').'>'
		if $myresult and defined $DNS_Cache{$myquery}{type} and defined $DNS_Cache{$myquery}{name};
	if ( wantsdebug (qw[ all verbose ]) or $postfwd_settings{dns}{anylog}
		or ($myresult and not($postfwd_settings{dns}{nolog}) and defined $DNS_Cache{$myquery}{'log'}) ) {
		log_info ("[DNSBL] ".( ($mytype eq $COMP_RBL_KEY) ? join('.', reverse(split(/\./,$myval))) : $myval )." listed on "
			.lc(($DNS_Cache{$myquery}{type} || $mytype)).":$myrbl (answer: ".(join ", ", @{$DNS_Cache{$myquery}{A}})
			.", time: ".ts($DNS_Cache{$myquery}{delay})."s, ttl: ".$DNS_Cache{$myquery}{ttl}."s, '".($DNS_Cache{$myquery}{TXT} || '')."')");
		delete $DNS_Cache{$myquery}{'log'} if defined $DNS_Cache{$myquery}{'log'};
	};
    };
    return $myresult;
};

# dns resolver wrapper
sub dns_query {
    my (@queries) = @_; undef my @result;
    eval {
        local $SIG{__DIE__} = sub { log_note ("[DNS] ERROR: \"$!\", DETAIL: \"@_\""); return if $^S; };
        @result = dns_query_net_dns(@queries);
    };
    return @result;
};

# resolves dns queries using Net::DNS
sub dns_query_net_dns {
    my (@queries) = @_; undef my @result; undef my $pans;
    my %ownsock  = (); my @ownready = (); undef my $bgsock;
    my $ownsel   = IO::Select->new();
    my $dns = Net::DNS::Resolver->new(
	tcp_timeout => $postfwd_settings{dns}{timeout},
	udp_timeout => $postfwd_settings{dns}{timeout},
	persistent_tcp => 0, persistent_udp => 0,
	retrans => 0, retry => 1, dnsrch => 0, defnames => 0,
    );
    my $now = time();
    # prepare queries
    foreach (@queries) {
	my ($item, $type) = split ','; $type ||= 'A';
	# query child cache
	if ( (defined $DNS_Cache{$item}{$type}) and (defined $DNS_Cache{$item}{'until'}) and ($DNS_Cache{$item}{'until'} >= $now) ) {
	    $DNS_Cache{$item}{$type} = [ $DNS_Cache{$item}{$type} ] unless (ref $DNS_Cache{$item}{$type} eq 'ARRAY');
	    log_info ("[DNS] dnsccache: item=$item, type=$type -> ".(join ',', @{$DNS_Cache{$item}{$type}})." (ttl: ".($DNS_Cache{$item}{ttl} || 0).")")
		if ($postfwd_settings{dns}{anylog} or wantsdebug (qw[ all dns getdns ]));
	    push @result, @{$DNS_Cache{$item}{$type}};
	# query parent cache
	} elsif (   not($postfwd_settings{dns}{noparent})
	    and not(($pans = cache_query ("CMD=".$postfwd_commands{getcacheitem}.";TYPE=dns;ITEM=$item")) eq '<undef>')
	    and (%{$DNS_Cache{$item}} = str_to_hash($pans))
	    and (defined $DNS_Cache{$item}{$type}) and (defined $DNS_Cache{$item}{'until'}) and ($DNS_Cache{$item}{'until'} >= $now) ) {
	    $DNS_Cache{$item}{$type} = [ $DNS_Cache{$item}{$type} ] unless (ref $DNS_Cache{$item}{$type} eq 'ARRAY');
	    log_info ("[DNS] dnspcache: item=$item, type=$type -> ".(join ',', @{$DNS_Cache{$item}{$type}})." (ttl: ".($DNS_Cache{$item}{ttl} || 0).")")
		if ($postfwd_settings{dns}{anylog} or wantsdebug (qw[ all dns getdns ]));
	    push @result, @{$DNS_Cache{$item}{$type}};
	# send queries
	} else {
	    log_info ("[DNS] dnsquery: item=$item, type=$type")
		if ($postfwd_settings{dns}{anylog} or wantsdebug (qw[ all dns getdns ]));
	    $DNS_Cache{$item}{delay} = $now;
	    $bgsock = $dns->bgsend ($item, $type);
	    $ownsel->add($bgsock);
	    $ownsock{$bgsock} = $item.','.$type;
	};
    };
    # retrieve answers
    while ((scalar keys %ownsock) and (@ownready = $ownsel->can_read($postfwd_settings{dns}{timeout}))) {
	foreach my $sock (@ownready) {
	    if (defined $ownsock{$sock}) {
		my $packet = $dns->bgread($sock);
		my ($item, $type) = split ',', $ownsock{$sock};
		my $rname = $DNS_REPNAMES{$type};
		my @rrs = (grep { $_->type eq $type } $packet->answer);
		$now = time(); my $ttl = 0; my @ans = ();
		if (@rrs) {
		    # sort MX records by preference
		    @rrs = sort { $a->preference <=> $b->preference } @rrs if ($type eq 'MX');
		    foreach my $rr (@rrs) {
			$ttl = $rr->ttl if ($rr->ttl > $ttl);
			log_info ("[DNS] dnsanswer: item=$item, type=$type -> $rname=".$rr->$rname." (ttl: $ttl)")
			    if ($postfwd_settings{dns}{anylog} or wantsdebug (qw[ all dns setdns ]));
			push @ans, $rr->$rname;
		    };
		    push @result, @ans;
		};
		# add to dns cache
		$ttl ||= $postfwd_settings{dns}{ttl};
		@{$DNS_Cache{$item}{$type}} = @ans;
		$DNS_Cache{$item}{ttl} = $ttl;
		$DNS_Cache{$item}{'until'} = $now + $ttl;
		$DNS_Cache{$item}{delay} = ($DNS_Cache{delay}) ? $now - $DNS_Cache{delay} : 0;
		cache_query ( "CMD=".$postfwd_commands{setcacheitem}.";TYPE=dns;ITEM=$item".hash_to_str(%{$DNS_Cache{$item}}) )
		    unless ($postfwd_settings{dns}{noparent});
		$DNS_Cache{$item}{'log'} = 1;
		log_info ("[DNS] dnsanswers: item=$item, type=$type -> $rname=".((@{$DNS_Cache{$item}{$type}}) ? join ',', @{$DNS_Cache{$item}{$type}} : '')." (delay: ".ts($DNS_Cache{$item}{delay}).", ttl: $ttl)")
		    if ($postfwd_settings{dns}{anylog} or wantsdebug (qw[ all verbose dns setdns ]));
		delete $ownsock{$sock};
	    } else {
		$ownsel->remove($sock);
		$sock = undef;
	    };
	};
    };
    # show timeouts
    map { log_note ("dnsquery: timeout for $_ after ".$postfwd_settings{dns}{timeout}." seconds") } (values %ownsock);
    return @result;
};


## SUB plugins

#
# these subroutines integrate additional attributes to
# a request before the ruleset is evaluated
# call: %result = postfwd_items{foo}(%request)
# save: $result{$_}
#
%postfwd_items = (
	"__builtin__" => sub {
		my(%request) = @_; my(%result) = ();
		# postfwd version
		$result{version} = $postfwd_settings{name}." ".$postfwd_settings{version};
		# sender info
		$request{sender} =~ /(.*)@([^@]*)$/;
		( $result{sender_localpart}, $result{sender_domain} ) = ( $1, $2 );
		# recipient info
		$request{recipient} =~ /(.*)@([^@]*)$/;
		( $result{recipient_localpart}, $result{recipient_domain} ) = ( $1, $2 );
		# reverted ip address (for lookups)
		$result{reverse_address} = (join(".", reverse(split(/\./,$request{client_address}))));
		return %result;
	},
	"sender_dns" => sub {
		my(%request) = @_; my(%result) = ();
		map { $result{$_} = $request{sender_domain} } ($COMP_NS_NAME, $COMP_NS_ADDR, $COMP_MX_NAME, $COMP_MX_ADDR);
		$result{$COMP_HELO_ADDR} = $request{helo_name};
		return %result;
	},
);
# returns additional request information
# for all postfwd_items
sub postfwd_items {
    my(%request) = @_;
    my(%result) = ();
    foreach (sort keys %postfwd_items) {
	log_info ("[PLUGIN] executing postfwd-item ".$_)
		if wantsdebug (qw[ all ]);
	%result = (%result, &{$postfwd_items{$_}}((%request,%result)))
		if (defined $postfwd_items{$_});
    };
    map { $result{$_} = '' unless $result{$_}; log_info ("[PLUGIN]  Added key: $_=$result{$_}") if wantsdebug (qw[ all ]) } (keys %result);
    return %result;
};
#
# compare item subroutines
# must take compare_item_foo ( $COMPARE_TYPE, $RULEITEM, $REQUESTITEM, %REQUEST, %REQUESTINFO );
#
%postfwd_compare = (
	"cidr" => sub {
		my($cmp,$val,$myitem,%request) = @_;
		my($myresult) = ($val and $myitem);
		log_info ("type cidr :  \"$myitem\"  \"$cmp\"  \"$val\"") if wantsdebug (qw[ all ]);
		if ($myresult) {
			# always true
			$myresult = ($val eq '0.0.0.0/0');
			unless ($myresult) {
				# v4 addresses only 
				$myresult = ($myitem =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/);
				if ($myresult) {
					$val .= '/32' unless ($val =~ /\/\d{1,2}$/);
					$myresult = cidr_match((cidr_parse($val)),$myitem);
				} else {
					log_info ("Non IPv4 address. Using type default") if wantsdebug (qw[ all ]);
					return &{$postfwd_compare{default}}($cmp,$val,$myitem,%request);
				};
			};
		};
		$myresult = not($myresult) if ($cmp eq '!=');
		return $myresult;
	},
	"numeric" => sub {
		my($cmp,$val,$myitem,%request) = @_;
		my($myresult) = undef;
		log_info ("type numeric :  \"$myitem\"  \"$cmp\"  \"$val\"") if wantsdebug (qw[ all ]);
		$myitem ||= "0"; $val ||= "0";
                if ($cmp eq '==') {
                        $myresult = ($myitem == $val);
                } elsif ($cmp eq '=<') {
                        $myresult = ($myitem <= $val);
                } elsif ($cmp eq '=>') {
                        $myresult = ($myitem >= $val);
                } elsif ($cmp eq '!=') {
                        $myresult = not($myitem == $val);
                } elsif ($cmp eq '!<') {
                        $myresult = not($myitem <= $val);
                } elsif ($cmp eq '!>') {
                        $myresult = not($myitem >= $val);
		} else {
			$myresult = ($myitem >= $val);
		};
		return $myresult;
	},
	$COMP_RBL_KEY => sub {
		my($cmp,$val,$myitem,%request) = @_;
		my($myresult) = not($postfwd_settings{dns}{disabled});
		log_info ("type rbl :  \"$myitem\"  \"$cmp\"  \"$val\"") if wantsdebug (qw[ all ]);
		$myresult = ( rbl_check ($COMP_RBL_KEY, $val, $myitem) ) if $myresult;
		$myresult = not($myresult) if ($cmp eq '!=');
		return $myresult;
	},
	$COMP_RHSBL_KEY => sub {
		my($cmp,$val,$myitem,%request) = @_;
		my($myresult) = not($postfwd_settings{dns}{disabled});
		log_info ("type rhsbl :  \"$myitem\"  \"$cmp\"  \"$val\"") if wantsdebug (qw[ all ]);
		$myresult = ( rbl_check ($COMP_RHSBL_KEY, $val, $myitem) ) if $myresult;
		$myresult = not($myresult) if ($cmp eq '!=');
		return $myresult;
	},
	$COMP_MONTHS => sub {
		my($cmp,$val,$myitem,%request) = @_;
		my($myresult) = undef;
		my($imon) = (split (',', $myitem))[4]; $imon ||= 0;
		my($rmin,$rmax) = split (/\s*-\s*/, $val);
		$rmin = ($rmin) ? (($rmin =~ /^\d$/) ? $rmin : $months{$rmin}) : $imon;
		$rmax = ($rmax) ? (($rmax =~ /^\d$/) ? $rmax : $months{$rmax}) : (($val =~ /-/) ? $imon : $rmin);
		log_info ("type months :  \"$imon\"  \"$cmp\"  \"$rmin\"-\"$rmax\"")
			if wantsdebug (qw[ all ]);
		$myresult = (($rmin <= $imon) and ($rmax >= $imon));
		$myresult = not($myresult) if ($cmp eq '!=');
		return $myresult;
	},
	$COMP_DAYS => sub {
		my($cmp,$val,$myitem,%request) = @_;
		my($myresult) = undef;
		my($iday) = (split (',', $myitem))[6]; $iday ||= 0;
		my($rmin,$rmax) = split (/\s*-\s*/, $val);
		$rmin = ($rmin) ? (($rmin =~ /^\d$/) ? $rmin : $weekdays{$rmin}) : $iday;
		$rmax = ($rmax) ? (($rmax =~ /^\d$/) ? $rmax : $weekdays{$rmax}) : (($val =~ /-/) ? $iday : $rmin);
		log_info ("type days :  \"$iday\"  \"$cmp\"  \"$rmin\"-\"$rmax\"")
			if wantsdebug (qw[ all ]);
		$myresult = (($rmin <= $iday) and ($rmax >= $iday));
		$myresult = not($myresult) if ($cmp eq '!=');
		return $myresult;
	},
	$COMP_DATE => sub {
		my($cmp,$val,$myitem,%request) = @_;
		my($myresult) = undef;
		my($isec,$imin,$ihour,$iday,$imon,$iyear) = split (',', $myitem);
		my($rmin,$rmax) = split (/\s*-\s*/, $val);
		my($idat) = ($iyear + 1900) . ((($imon+1) < 10) ? '0'.($imon+1) : ($imon+1)) . (($iday < 10) ? '0'.$iday : $iday);
		$rmin = ($rmin) ? join ('', reverse split ('\.', $rmin)) : $idat;
		$rmax = ($rmax) ? join ('', reverse split ('\.', $rmax)) : (($val =~ /-/) ? $idat : $rmin);
		log_info ("type date :  \"$idat\"  \"$cmp\"  \"$rmin\"-\"$rmax\"")
			if wantsdebug (qw[ all ]);
		$myresult = (($rmin <= $idat) and ($rmax >= $idat));
		$myresult = not($myresult) if ($cmp eq '!=');
		return $myresult;
	},
	$COMP_TIME => sub {
		my($cmp,$val,$myitem,%request) = @_;
		my($myresult) = undef;
		my($isec,$imin,$ihour,$iday,$imon,$iyear) = split (',', $myitem);
		my($rmin,$rmax) = split (/\s*-\s*/, $val);
		my($idat) = (($ihour < 10) ? '0'.$ihour : $ihour) . (($imin < 10) ? '0'.$imin : $imin) . (($isec < 10) ? '0'.$isec : $isec);
		$rmin = ($rmin) ? join ('', split ('\:', $rmin)) : $idat;
		$rmax = ($rmax) ? join ('', split ('\:', $rmax)) : (($val =~ /-/) ? $idat : $rmin);
		log_info ("type time :  \"$idat\"  \"$cmp\"  \"$rmin\"-\"$rmax\"")
			if wantsdebug (qw[ all ]);
		$myresult = (($rmin <= $idat) and ($rmax >= $idat));
		$myresult = not($myresult) if ($cmp eq '!=');
		return $myresult;
	},
	$COMP_HELO_ADDR => sub {
		my($cmp,$val,$myitem,%request) = @_;
		my($myresult) = undef;
		return $myresult if $postfwd_settings{dns}{disabled};
		return $myresult unless $myitem =~ /\./;
		if ( my @answers = dns_query ("$myitem,A") ) {
			log_info ("type $COMP_HELO_ADDR : \"".(join ',', @answers)."\"  \"$cmp\"  \"$val\"") if wantsdebug (qw[ all ]);
			map { $myresult = ( &{$postfwd_compare{cidr}}(($cmp,$val,$_,%request)) ); return $myresult if $myresult } @answers;
		};
		return $myresult;
	},
	$COMP_NS_NAME => sub {
		my($cmp,$val,$myitem,%request) = @_;
		my($myresult) = undef;
		return $myresult if $postfwd_settings{dns}{disabled};
		return $myresult unless $myitem =~ /\./;
		if ( my @answers = dns_query ("$myitem,NS") ) {
			log_info ("type $COMP_NS_NAME : \"".(join ',', @answers)."\"  \"$cmp\"  \"$val\"") if wantsdebug (qw[ all ]);
			map { $myresult = ( &{$postfwd_compare{default}}(($cmp,$val,$_,%request)) ); return $myresult if $myresult } @answers;
		} else {
			$myresult = ( &{$postfwd_compare{default}}(($cmp,$val,'',%request)) );
		};
		return $myresult;
	},
	$COMP_MX_NAME => sub {
		my($cmp,$val,$myitem,%request) = @_;
		my($myresult) = undef;
		return $myresult if $postfwd_settings{dns}{disabled};
		return $myresult unless $myitem =~ /\./;
		if ( my @answers = dns_query ("$myitem,MX") ) {
			log_info ("type $COMP_MX_NAME : \"".(join ',', @answers)."\"  \"$cmp\"  \"$val\"") if wantsdebug (qw[ all ]);
			map { $myresult = ( &{$postfwd_compare{default}}(($cmp,$val,$_,%request)) ); return $myresult if $myresult } @answers;
		} else {
			$myresult = ( &{$postfwd_compare{default}}(($cmp,$val,'',%request)) );
		};
		return $myresult;
	},
	$COMP_NS_ADDR => sub {
		my($cmp,$val,$myitem,%request) = @_;
		my($myresult) = undef;
		return $myresult if $postfwd_settings{dns}{disabled};
		return $myresult unless $myitem =~ /\./;
		if ( my @answers = dns_query ("$myitem,NS") ) {
			splice (@answers, $postfwd_settings{dns}{max_ns_lookups}) if $postfwd_settings{dns}{max_ns_lookups} and $#answers > $postfwd_settings{dns}{max_ns_lookups};
			if ( @answers = dns_query (@answers) ) {
				log_info ("type $COMP_NS_ADDR : \"".(join ',', @answers)."\"  \"$cmp\"  \"$val\"") if wantsdebug (qw[ all ]);
				map { $myresult = ( &{$postfwd_compare{cidr}}(($cmp,$val,$_,%request)) ); return $myresult if $myresult } @answers;
			};
		};
		return $myresult;
	},
	$COMP_MX_ADDR => sub {
		my($cmp,$val,$myitem,%request) = @_;
		my($myresult) = undef;
		return $myresult if $postfwd_settings{dns}{disabled};
		return $myresult unless $myitem =~ /\./;
		if ( my @answers = dns_query ("$myitem,MX") ) {
			splice (@answers, $postfwd_settings{dns}{max_mx_lookups}) if $postfwd_settings{dns}{max_mx_lookups} and $#answers > $postfwd_settings{dns}{max_mx_lookups};
			if ( @answers = dns_query (@answers) ) {
				log_info ("type $COMP_MX_ADDR : \"".(join ',', @answers)."\"  \"$cmp\"  \"$val\"") if wantsdebug (qw[ all ]);
				map { $myresult = ( &{$postfwd_compare{cidr}}(($cmp,$val,$_,%request)) ); return $myresult if $myresult } @answers;
			};
		};
		return $myresult;
	},
	"default" => sub {
		my($cmp,$val,$myitem,%request) = @_;
		my($var,$myresult) = undef;
		log_info ("type default :  \"$myitem\"  \"$cmp\"  \"$val\"") if wantsdebug (qw[ all ]);
		# backward compatibility
		$cmp = '==' if ( ($var) and ($cmp eq '=') );
		if ($cmp eq '==') {
			$myresult = ( lc($myitem) eq lc($val) ) if $myitem;
		} elsif ($cmp eq '!=') {
			$myresult = not( lc($myitem) eq lc($val) ) if $myitem;
		} elsif ($cmp eq '=<') {
			$myresult = (($myitem || 0) <= $val);
		} elsif ($cmp eq '!<') {
			$myresult = not(($myitem || 0) <= $val);
		} elsif ($cmp eq '=>') {
			$myresult = (($myitem || 0) >= $val);
		} elsif ($cmp eq '!>') {
			$myresult = not(($myitem || 0) >= $val);
		} elsif ($cmp eq '=~') {
			$myresult = ($myitem =~ /$val/i);
		} elsif ($cmp eq '!~') {
			$myresult = ($myitem !~ /$val/i);
		} else {
			# allow // regex
			$val =~ s/^\/?(.*?)\/?$/$1/;
			$myresult = $myitem =~ /$val/i;
		};
		return $myresult;
	},
	"client_address"	=> sub { return &{$postfwd_compare{cidr}}(@_); },
	"encryption_keysize"	=> sub { return &{$postfwd_compare{numeric}}(@_); },
	"size"			=> sub { return &{$postfwd_compare{numeric}}(@_); },
	"recipient_count"	=> sub { return &{$postfwd_compare{numeric}}(@_); },
	"request_score"		=> sub { return &{$postfwd_compare{numeric}}(@_); },
	$COMP_RHSBL_KEY_CLIENT	=> sub { return &{$postfwd_compare{$COMP_RHSBL_KEY}}(@_); },
	$COMP_RHSBL_KEY_SENDER	=> sub { return &{$postfwd_compare{$COMP_RHSBL_KEY}}(@_); },
	$COMP_RHSBL_KEY_HELO	=> sub { return &{$postfwd_compare{$COMP_RHSBL_KEY}}(@_); },
	$COMP_RHSBL_KEY_RCLIENT	=> sub { return &{$postfwd_compare{$COMP_RHSBL_KEY}}(@_); },
);
#
# these subroutines define postfwd actions
#
%postfwd_actions = (
	# example action foo()
	# "foo" => sub {
	#	my($index,$now,$mycmd,$myarg,$myline,%request) = @_;
	#	my($myaction) = $postfwd_settings{default}; my($stop) = 0;
	#	...
	#	return ($stop,$index,$myaction,$myline,%request);
	# },
	# jump() command
	"jump"	=> sub {
		my($index,$now,$mycmd,$myarg,$myline,%request) = @_;
		my($myaction) = $postfwd_settings{default}; my($stop) = 0;
		if (defined $Rule_by_ID{$myarg}) {
			my($ruleno) = $Rule_by_ID{$myarg};
			log_info ("[RULES] ".$myline
				.", jump to rule $ruleno (id $myarg)")
				if wantsdebug (qw[ all verbose ]);
			$index = $ruleno - 1;
		} else {
			log_warn ("[RULES] ".$myline." - error: jump failed, can not find rule-id ".$myarg." - ignoring");
		};
		return ($stop,$index,$myaction,$myline,%request);
	},
	# set() command
	"set"	=> sub {
		my($index,$now,$mycmd,$myarg,$myline,%request) = @_;
		my($myaction) = $postfwd_settings{default}; my($stop) = 0;
		foreach ( split (",", $myarg) ) {
			if ( /^\s*([^=]+?)\s*([\.\-\*\/\+=]=|=[\.\-\*\/\+=]|=)\s*(.*?)\s*$/ ) {
				my($r_var, $mod, $r_val) = ($1, $2, $3);
				my($m_val) = (defined $request{$r_var}) ? $request{$r_var} : 0;
				# saves some ifs
				if (($mod eq '=') or ($mod eq '==')) {
					$m_val = $r_val;
				} elsif ( ($mod eq '.=') or ($mod eq '=.') ) {
					$m_val .= $r_val;
				} elsif ( (($mod eq '+=') or ($mod eq '=+')) and (($m_val=~/^\d+(\.\d+)?$/) and ($r_val=~/^\d+(\.\d+)?$/)) ) {
					$m_val += $r_val;
				} elsif ( (($mod eq '-=') or ($mod eq '=-')) and (($m_val=~/^\d+(\.\d+)?$/) and ($r_val=~/^\d+(\.\d+)?$/)) ) {
					$m_val -= $r_val;
				} elsif ( (($mod eq '*=') or ($mod eq '=*')) and (($m_val=~/^\d+(\.\d+)?$/) and ($r_val=~/^\d+(\.\d+)?$/)) ) {
					$m_val *= $r_val;
				} elsif ( (($mod eq '/=') or ($mod eq '=/')) and (($m_val=~/^\d+(\.\d+)?$/) and ($r_val=~/^\d+(\.\d+)?$/)) ) {
					$m_val /= (($r_val == 0) ? 1 : $r_val);
				} else {
					$m_val = $r_val;
				};
				$m_val = $1.((defined $2) ? $2 : '') if ( $m_val =~ /^(\-?\d+)([\.,]\d\d?)?/ );
				(defined $request{$r_var})
					? log_info ("notice", "[RULES] ".$myline.", redefining existing ".$r_var."=".$request{$r_var}." with ".$r_var."=".$m_val)
					: log_info ("[RULES] ".$myline.", defining ".$r_var."=".$m_val)
					if wantsdebug (qw[ all verbose ]);
				$request{$r_var} = $m_val;
			} else {
				log_warn ("[RULES] ".$myline.", ignoring unknown set() attribute ".$_);
			};
		};
		return ($stop,$index,$myaction,$myline,%request);
	},
	# score() command
	"score"	=> sub {
		my($index,$now,$mycmd,$myarg,$myline,%request) = @_;
		my($myaction) = $postfwd_settings{default}; my($stop) = 0;
		my($score) = (defined $request{request_score}) ? $request{request_score} : 0;
		if ($myarg =~/^([\+\-\*\/\=]?)(\d+)([\.,](\d+))?$/) {
			my($mod, $val) = ($1, $2 + ((defined $4) ? ($4 / 10) : 0));
			if ($mod eq '-') {
				$score -= $val;
			} elsif ($mod eq '*') {
				$score *= $val;
			} elsif ($mod eq '/') {
				$score /= $val unless ($val == 0);
			} elsif ($mod eq '=') {
				$score = $val;
			} else {
				$score += $val;
			};
			$score = $1.((defined $2) ? $2 : '.0') if ( $score =~ /^(\-?\d+)([\.,]\d\d?)?/ );
			log_info ("[SCORE] ".$myline.", modifying score about ".$myarg." points to ". $score)
				if wantsdebug (qw[ all verbose ]);
			$request{score} = $request{request_score} = $score;
		} elsif ($myarg) {
			log_warn ("[RULES] ".$myline.", invalid value for score \"$myarg\" - ignoring");
		};
		MAXSCORE: foreach my $max_score (reverse sort keys %{$postfwd_settings{scores}}) {
			if ( ($score >= $max_score) and ($postfwd_settings{scores}{$max_score}) ) {
				$myaction=$postfwd_settings{scores}{$max_score};
				$myline .= ", score=".$score."/".$max_score;
				$stop = $score; last MAXSCORE;
			};
		};
		return ($stop,$index,$myaction,$myline,%request);
	},
	# rate() command
	"rate"	=> sub {
		my($index,$now,$mycmd,$myarg,$myline,%request) = @_;
		my($myaction) = $postfwd_settings{default}; my($stop) = 0; my $prate = '';
		my($ratetype,$ratecount,$ratetime,$ratecmd) = split "/", $myarg, 4;
		if ($ratetype and $ratecount and $ratetime and $ratecmd) {
		  my $crate = $Rules[$index]{$COMP_ID}.'+'.$ratecount.'_'.$ratetime;
		  if ( defined $request{$ratetype} ) {
			$ratetype .= "=".$request{$ratetype};

			# Check if rate already exists in cache
			my $rate_exists = ( defined $Rate_Cache{$ratetype}{$crate} );
			if ( $rate_exists ) {
				# Child hit
				log_info ("[RULES] rate limit object '".$ratetype."' '".$crate."' exists in local cache") if wantsdebug (qw[ all rates ]);
			# Query parent cache
			} elsif ( not $postfwd_settings{rate}{noparent} ) {
				my $prate = "CMD=".$postfwd_commands{getrateitem}.";TYPE=rate;ITEM=$ratetype".$postfwd_settings{seplim}.$crate;
				log_info ("[RULES] query parent cache: '$prate'") if wantsdebug (qw[ all rates ]);
				$prate = cache_query($prate);
				log_info ("[RULES] parent cache answer: '$prate'") if wantsdebug (qw[ all rates ]);
				$rate_exists = ( $prate ne '<undef>' );
				if ( $rate_exists ) {
					# Parent hit, populate local cache
					%{$Rate_Cache{$ratetype}{$crate}} = str_to_hash($prate);
					push @{$Rate_Cache{$ratetype}{'list'}}, $crate;
					@{$Rate_Cache{$ratetype}{'list'}} = uniq(@{$Rate_Cache{$ratetype}{'list'}});
				};
			};

			unless ( $rate_exists ) {
				log_info ("[RULES] ".$myline
					.", creating rate limit object '".$ratetype."' '".$crate."'"
					." [type: ".$mycmd.", max: ".$ratecount.", time: ".$ratetime."s]")
					if wantsdebug (qw[ all rates ]);
				push @{$Rate_Cache{$ratetype}{'list'}}, $crate;
				@{$Rate_Cache{$ratetype}{'list'}} = uniq(@{$Rate_Cache{$ratetype}{'list'}});
				$Rate_Cache{$ratetype}{$crate} = {
					type 		=> $mycmd,
					maxcount	=> $ratecount,
					ttl		=> $ratetime,
					time		=> $now,
					'until'		=> $now + $ratetime,
					count		=> ( ($mycmd eq 'size') ? $request{size} : (($mycmd eq 'rcpt') ? $request{recipient_count} : 1 ) ),
					rule		=> $Rules[$index]{$COMP_ID},
					action		=> $ratecmd,
				};
				unless ($postfwd_settings{rate}{noparent}) {
					$prate = "CMD=".$postfwd_commands{setrateitem}.";TYPE=rate;ITEM=$ratetype".$postfwd_settings{seplim}.$crate.hash_to_str(%{$Rate_Cache{$ratetype}{$crate}});
					log_info ("creating parent rate limit object '".$prate."'") if wantsdebug (qw[ all rates setcache ]);
					cache_query ($prate);
				};
			};
		  } else {
			log_note ("[RULES] ".$myline.", ignoring empty index for ".$mycmd." limit '".$ratetype."'") if wantsdebug (qw[ all rates ]);
		  };
		} else {
			log_note ("[RULES] ".$myline.", ignoring unknown ".$mycmd."() attribute \'".$myarg."\'");
		};
		return ($stop,$index,$myaction,$myline,%request);
	},
	# size() command
	"size"	=> sub { return &{$postfwd_actions{rate}}(@_); },
	# rcpt() command
	"rcpt"	=> sub { return &{$postfwd_actions{rate}}(@_); },
	# wait() command
	"wait"	=> sub {
		my($index,$now,$mycmd,$myarg,$myline,%request) = @_;
		my($myaction) = $postfwd_settings{default}; my($stop) = 0;
		log_info ("[RULES] ".$myline.", delaying for $myarg seconds");
		sleep $myarg;
		return ($stop,$index,$myaction,$myline,%request);
	},
	# note() command
	"note"	=> sub {
		my($index,$now,$mycmd,$myarg,$myline,%request) = @_;
		my($myaction) = $postfwd_settings{default}; my($stop) = 0;
		log_info ("[RULES] ".$myline." - note: ".$myarg) if $myarg;
		return ($stop,$index,$myaction,$myline,%request);
	},
	# quit() command - not supported in this version
	"quit"	=> sub {
		my($index,$now,$mycmd,$myarg,$myline,%request) = @_;
		log_warn ("[RULES] ".$myline." - critical: quit (".$myarg.") unsupported in this version - ignoring");
	},
	# file() command
	"file"	=> sub {
		my($index,$now,$mycmd,$myarg,$myline,%request) = @_;
		my($myaction) = $postfwd_settings{default}; my($stop) = 0;
		log_warn ("[RULES] ".$myline." - error: command ".$mycmd."() has not been implemented yet - ignoring");
		return ($stop,$index,$myaction,$myline,%request);
	},
	# ask() command
	"ask"  => sub {
		my($index,$now,$mycmd,$myarg,$myline,%request) = @_;
		my($myaction) = $postfwd_settings{default}; my($stop) = 0;
		log_info ("Opening socket to '$myarg'") if wantsdebug (qw[ all ]);
		my($addr,$port,$ignore) = split ':', $myarg;
		my %orig = str_to_hash ($request{orig});
		if ( ($addr and $port) and my $socket = new IO::Socket::INET (
			PeerAddr => $addr,
			PeerPort => $port,
			Proto    => 'tcp',
			Timeout  => 9,
			Type     => SOCK_STREAM	) ) {

				my $sendstr = '';
				foreach (keys %orig) {
					$sendstr .= $_."=".$orig{$_}."\n";
				};
				$sendstr .= "\n";
				log_info ("Asking service $myarg -> '$sendstr'") if wantsdebug (qw[ all ]);
				print $socket "$sendstr";
				$sendstr = <$socket>;
				chomp($sendstr);
				log_info ("Answer from $myarg -> '$sendstr'") if wantsdebug (qw[ all verbose ]);
				$sendstr =~ s/^(action=)//;
				if ($1 and $sendstr) {
					if ($ignore and ($sendstr =~ /$ignore/i)) {
						log_info ("ignoring answer '$sendstr' from $myarg") if wantsdebug (qw[ all verbose ]);
					} else {
						$stop = $myaction = $sendstr;
					};
				} else {
					log_note ("rule: $index got invalid answer '$sendstr' from $myarg");
				};
		} else {
			log_note ("Could not open socket to '$myarg' - $!");
		};
		return ($stop,$index,$myaction,$myline,%request);
	},
	# exec() command
	"exec"	=> sub { return &{$postfwd_actions{file}}(@_); },
);

# load plugin-items
sub get_plugins {
    my(@pluginfiles) = @_;
    my($pluginlog)   = '';    
    foreach my $file (@pluginfiles) {
	unless ( -e $file ) {
		log_warn ("File not found: $file");
	} else {
		$file =~ /^(.*)$/;
		require $1 if $1;
		map { delete $postfwd_items_plugin{$_}   unless ($_ and defined $postfwd_items_plugin{$_})   } (keys %postfwd_items_plugin);
		map { delete $postfwd_compare_plugin{$_} unless ($_ and defined $postfwd_compare_plugin{$_}) } (keys %postfwd_compare_plugin);
		map { delete $postfwd_actions_plugin{$_} unless ($_ and defined $postfwd_actions_plugin{$_}) } (keys %postfwd_actions_plugin);
		map { log_note ("[PLUGIN] overriding prior item \'".$_."\'") 		 if (defined $postfwd_items{$_})   } (keys %postfwd_items_plugin);
		map { log_note ("[PLUGIN] overriding prior compare function \'".$_."\'") if (defined $postfwd_compare{$_}) } (keys %postfwd_compare_plugin);
		map { log_note ("[PLUGIN] overriding prior action \'".$_."\'") 		 if (defined $postfwd_actions{$_}) } (keys %postfwd_actions_plugin);
		%postfwd_items   = ( %postfwd_items, %postfwd_items_plugin )     if %postfwd_items_plugin;
		%postfwd_compare = ( %postfwd_compare, %postfwd_compare_plugin ) if %postfwd_compare_plugin;
		%postfwd_actions = ( %postfwd_actions, %postfwd_actions_plugin ) if %postfwd_actions_plugin;
		$pluginlog =  "[PLUGIN] Loaded plugins file: ".$file;
		$pluginlog .= " items: \"".(join ", ", (sort keys %postfwd_items_plugin))."\""
			if %postfwd_items_plugin;
		$pluginlog .= " compare: \"".(join ", ", (sort keys %postfwd_compare_plugin))."\""
			if %postfwd_compare_plugin;
		$pluginlog .= " actions: \"".(join ", ", (sort keys %postfwd_actions_plugin))."\""
			if %postfwd_actions_plugin;
		log_info ($pluginlog);
	};
    };
};


### SUB ruleset

# compare item main
# use: compare_item ( $TYPE, $RULEITEM, $MINIMUMHITS, $REQUESTITEM, %REQUEST, %REQUESTINFO );
sub compare_item {
    my($mykey,$mymask,$mymin,$myitem, %request) = @_;
    my($val,$var,$cmp,$neg,$myresult,$postfwd_compare_proc);
    my($rcount) = 0;
    $mymin ||= 1;

    #
    # determine the right compare function
    $postfwd_compare_proc = (defined $postfwd_compare{$mykey}) ? $mykey : "default";
    #
    # save list due to possible modification
    my @items = @{$mymask};
    # now compare request to every single item
    ITEM: foreach (@items) {
	($cmp, $val) = split ";";
	next ITEM unless ($cmp and $val and $mykey);
	# prepare_file
	if ($val =~ /$COMP_LIVE_FILE_TABLE/) {
		push @items, prepare_file (0, $1, $cmp, $2);
		next ITEM;
	};
	log_info ("compare $mykey:  \"$myitem\"  \"$cmp\"  \"$val\"") if wantsdebug (qw[ all ]);
	$val = $neg if ($neg = deneg_item($val));
	log_info ("deneg $mykey:  \"$myitem\"  \"$cmp\"  \"$val\"") if ($neg and wantsdebug (qw[ all ]));
	next ITEM unless $val;
	# substitute check for $$vars in rule item
	if ( $var = devar_item ($cmp,$val,$myitem,%request) ) {
		$val = $var; $val =~ s/([^-_@\.\w\s])/\\$1/g unless ($cmp eq '==');
	};
	$myresult = &{$postfwd_compare{$postfwd_compare_proc}}($cmp,$val,$myitem,%request);
	log_info ("match $mykey:  ".($myresult ? "TRUE" : "FALSE")) if wantsdebug (qw[ all ]);
	if ($neg) {
		$myresult = not($myresult);
		log_info ("negate match $mykey:  ".($myresult ? "TRUE" : "FALSE")) if wantsdebug (qw[ all ]);
	};
	$rcount++ if $myresult;
	$myresult = not($mymin eq 'all');
	$myresult = ( $rcount >= $mymin ) if $myresult;
	log_info ("count $mykey:  request=$rcount  minimum: $mymin  result: ".($myresult ? "TRUE" : "FALSE")) if wantsdebug (qw[ all ]);
	last ITEM if $myresult;
    };
    $myresult = $rcount if ($myresult or ($mymin eq 'all'));
    return $myresult;
};


#
# compare request against a single rule
#
sub compare_rule {
    my($index,$date,%request) = @_;
    my(@ruleitems) = keys %{$Rules[$index]};
    my($has_rbl) = exists($Rules[$index]{$COMP_RBL_KEY});
    my($has_rhl) = (
	exists($Rules[$index]{$COMP_RHSBL_KEY}) or exists($Rules[$index]{$COMP_RHSBL_KEY_RCLIENT}) or
	exists($Rules[$index]{$COMP_RHSBL_KEY_CLIENT}) or exists($Rules[$index]{$COMP_RHSBL_KEY_SENDER}) or
	exists($Rules[$index]{$COMP_RHSBL_KEY_HELO})
    );
    my($has_senderdns) = ( exists($Rules[$index]{$COMP_NS_NAME})
			or exists($Rules[$index]{$COMP_MX_NAME})
			or exists($Rules[$index]{$COMP_NS_ADDR})
			or exists($Rules[$index]{$COMP_MX_ADDR})
    );
    my($hasdns) = ( not($postfwd_settings{dns}{disabled}) and ($has_senderdns or $has_rhl or $has_rbl) );
    my($mykey,$myitem,$val,$cmp,$res,$myline,$timed) = undef;
    my(@myresult) = (0,0,0,0);
    my(@queries,@timedout) = ();
    my($num) = 1;
    undef @DNSBL_Text;
    my($ownres,$ownsel,$bgsock) = undef;
    my %ownsock  = ();
    my @ownready = ();

    log_info ("[RULES] rule: $index, id: $Rules[$index]{$COMP_ID}, items: '".((@ruleitems) ? join ';', @ruleitems: '')."'") if wantsdebug (qw[ all ]);

    # COMPARE-ITEMS
    # check all non-dns items
    ITEM: for $mykey ( keys %{$Rules[$index]} ) {
	# always true
	if ( ($mykey eq $COMP_ID) or ($mykey eq $COMP_ACTION) or ($mykey eq $COMP_CACHE) ) {
		$myresult[0]++;
		next ITEM;
	};
	next ITEM if ( (($mykey eq $COMP_RBL_CNT) or ($mykey eq $COMP_RHSBL_CNT)) );
	next ITEM if ( (($mykey eq $COMP_RBL_KEY) or ($mykey eq $COMP_RHSBL_KEY)) );
	next ITEM if ( ($mykey eq $COMP_RHSBL_KEY_RCLIENT) or ($mykey eq $COMP_RHSBL_KEY_CLIENT) or ($mykey eq $COMP_RHSBL_KEY_SENDER) or ($mykey eq $COMP_RHSBL_KEY_HELO) );

	# integration at this point enables redefining scores within ruleset
	if ($mykey eq $COMP_SCORES) {
		modify_score ($Rules[$index]{$mykey},$Rules[$index]{$COMP_ACTION});
		$myresult[0] = 0;
	} else {
		$val = ( $mykey =~ /^$COMP_DATECALC$/ )
			# prepare date check
			? $date
			# default: compare against request attribute
			: $request{$mykey};
		$myresult[0] = ($res = compare_item($mykey, $Rules[$index]{$mykey}, $num, ($val || ''), %request)) ? ($myresult[0] + $res) : 0;
	};
	last ITEM unless ($myresult[0] > 0);
    };
    log_info ("[RULES] pre-dns: rule: $index, id: $Rules[$index]{$COMP_ID}, RESULT: ".$myresult[0]) if wantsdebug (qw[ all ]);

    # DNSQUERY-SECTION
    # fire bgsend()s with callback to result cache,
    # if they are not contained already,
    # and $postfwd_settings{dns}{disabled} is not set
    if ($hasdns and $myresult[0]) {

	# prepare dns queries
	$ownres   = Net::DNS::Resolver->new(
		tcp_timeout => $postfwd_settings{dns}{timeout},
		udp_timeout => $postfwd_settings{dns}{timeout},
		persistent_tcp => 0, persistent_udp => 0,
		retrans => 0, retry => 1, dnsrch => 0, defnames => 0,
	);
	$ownsel   = IO::Select->new();

	map { $timed .= (($timed) ? ", $_" : $_) if $Timeouts{$_} > $postfwd_settings{dns}{max_timeout} } (keys %Timeouts);
	log_note ("[DNSBL] skipping rbls: $timed - too much timeouts") if $timed;

	push @queries, rbl_prepare_lookups ( $COMP_RBL_KEY, $request{reverse_address}, @{$Rules[$index]{$COMP_RBL_KEY}} )
		if (defined $Rules[$index]{$COMP_RBL_KEY});

	push @queries, rbl_prepare_lookups ( $COMP_RHSBL_KEY, $request{client_name}, @{$Rules[$index]{$COMP_RHSBL_KEY}} )
		if (defined $Rules[$index]{$COMP_RHSBL_KEY});

	push @queries, rbl_prepare_lookups ( $COMP_RHSBL_KEY_CLIENT, $request{client_name}, @{$Rules[$index]{$COMP_RHSBL_KEY_CLIENT}} )
		if (defined $Rules[$index]{$COMP_RHSBL_KEY_CLIENT});

	push @queries, rbl_prepare_lookups ( $COMP_RHSBL_KEY_RCLIENT, $request{reverse_client_name}, @{$Rules[$index]{$COMP_RHSBL_KEY_RCLIENT}} )
		if (defined $Rules[$index]{$COMP_RHSBL_KEY_RCLIENT});

	push @queries, rbl_prepare_lookups ( $COMP_RHSBL_KEY_HELO, $request{helo_name}, @{$Rules[$index]{$COMP_RHSBL_KEY_HELO}} )
		if (defined $Rules[$index]{$COMP_RHSBL_KEY_HELO});

	push @queries, rbl_prepare_lookups ( $COMP_RHSBL_KEY_SENDER, $request{sender_domain}, @{$Rules[$index]{$COMP_RHSBL_KEY_SENDER}} )
		if (defined $Rules[$index]{$COMP_RHSBL_KEY_SENDER});

	# send dns queries
	if ( @queries ) {
		@queries = uniq(@queries);
		QUERY: foreach my $query (@queries) {
			next QUERY unless $query;
			log_info ("[SENDDNS] sending query \'$query\'")
				if wantsdebug (qw[ all ]);
			# send A query
			$bgsock = $ownres->bgsend($query, 'A');
			$ownsel->add($bgsock);
			$ownsock{$bgsock} = 'A:'.$query;
			# send TXT query
			if ($postfwd_settings{dns}{async_txt}) {
				$bgsock = $ownres->bgsend($query, 'TXT');
				$ownsel->add($bgsock);
				$ownsock{$bgsock} = 'TXT:'.$query;
			};
		};
		log_info ("[SENDDNS] rule: $index, id: $Rules[$index]{$COMP_ID}, lookups: ".($#queries + 1))
			if wantsdebug (qw[ all ]);
		$myresult[3] = "dnsqueries=".($#queries + 1).$postfwd_settings{sepreq}."dnsinterval=".($#queries + 1);
	};

        # DNSRESULT-SECTION
        # wait for select() and check the results unless $postfwd_settings{dns}{disabled}
	my($ownstart) = time(); @queries = ();
	while ((scalar keys %ownsock) and (@ownready = $ownsel->can_read($postfwd_settings{dns}{timeout}))) {
		foreach my $sock (@ownready) {
			if (defined $ownsock{$sock}) {
				log_note ("[DNSBL] answer for ".$ownsock{$sock})
					if wantsdebug (qw[ all ]);
				my $packet = $ownres->bgread($sock);
				push @queries, (split ':', $ownsock{$sock})[1] if rbl_read_dns ($packet);
				delete $ownsock{$sock};
			} else {
				$ownsel->remove($sock);
				$sock = undef;
			};
		};
	};

	# timeout handling
	map { push @timedout, (split ':', $ownsock{$_})[1] } (keys %ownsock);
	if (@timedout) {
		@timedout = uniq(@timedout);
		$myresult[3] .= $postfwd_settings{sepreq}."dnstimeouts=".($#timedout + 1);
		foreach (@timedout) {
			my $now = time();
		#	@{$DNS_Cache{$_}{A}}    = ('__TIMEOUT__');
			$DNS_Cache{$_}{ttl}     = $postfwd_settings{dns}{ttl} unless $DNS_Cache{$_}{ttl};
			$DNS_Cache{$_}{'delay'} = $now - $ownstart;
			$DNS_Cache{$_}{'until'} = $now + $DNS_Cache{$_}{ttl};
			$DNS_Cache{$_}{'timed'} = 1;
			$Timeouts{$DNS_Cache{$_}{name}} = (defined $Timeouts{$DNS_Cache{$_}{name}})
				? $Timeouts{$DNS_Cache{$_}{name}} + 1
				: 1
				if ( $postfwd_settings{dns}{max_timeout} > 0 );
			log_note ("[DNSBL] warning: timeout (".$Timeouts{$DNS_Cache{$_}{name}}."/".$postfwd_settings{dns}{max_timeout}.") for ".$DNS_Cache{$_}{name}." after ".ts($DNS_Cache{$_}{'delay'})." seconds");
		};
	};

        # perform outstanding TXT queries unless --dns_async_txt is set
        if (not($postfwd_settings{dns}{async_txt}) and @queries) {
                @queries = uniq(@queries);
                log_info ("[DNSBL] sending TXT queries for ".(join ',', @queries)) if wantsdebug (qw[ all debugdns ]);
                foreach my $query (@queries) {
                        log_info ("[SENDDNS] sending TXT query \'$query\'") if wantsdebug (qw[ all ]);
                        # send TXT query
                        $bgsock = $ownres->bgsend($query, 'TXT');
                        $ownsel->add($bgsock);
                        $ownsock{$bgsock} = 'TXT:'.$query;
                };
                while ((scalar keys %ownsock) and (@ownready = $ownsel->can_read($postfwd_settings{dns}{timeout}))) {
                        foreach my $sock (@ownready) {
                                if (defined $ownsock{$sock}) {
                                        log_info ("[DNSBL] answer for ".$ownsock{$sock})
                                                if wantsdebug (qw[ all ]);
                                        my $packet = $ownres->bgread($sock);
                                        rbl_read_dns ($packet);
                                        delete $ownsock{$sock};
                                } else {
                                        $ownsel->remove($sock);
                                        $sock = undef;
                                };
                        };
                };
        };

	# compare dns results
	if ( ($myresult[0] > 0) and exists($Rules[$index]{$COMP_RBL_KEY}) ) {
		$res = compare_item(
			$COMP_RBL_KEY,
			$Rules[$index]{$COMP_RBL_KEY},
			($Rules[$index]{$COMP_RBL_CNT} ||= 1),
			$request{reverse_address},
			%request
		);
		$myresult[0] = ($res or ($Rules[$index]{$COMP_RBL_CNT} eq 'all')) ? ($myresult[0] + $res) : 0;
		$myresult[1] = ($res) ? $res : 0;
	};

	if ( $has_rhl and ($myresult[0] > 0) ) {
		if ( exists($Rules[$index]{$COMP_RHSBL_KEY}) ) {
				$res = compare_item(
					$COMP_RHSBL_KEY,
					$Rules[$index]{$COMP_RHSBL_KEY},
					($Rules[$index]{$COMP_RHSBL_CNT} ||= 1),
					$request{client_name},
					%request
				);
				$myresult[0] = ($res or ($Rules[$index]{$COMP_RHSBL_CNT} eq 'all')) ? ($myresult[0] + $res) : 0;
				$myresult[2] += $res if $res;
		};
		if ( exists($Rules[$index]{$COMP_RHSBL_KEY_CLIENT}) ) {
				$res = compare_item(
					$COMP_RHSBL_KEY_CLIENT,
					$Rules[$index]{$COMP_RHSBL_KEY_CLIENT},
					($Rules[$index]{$COMP_RHSBL_CNT} ||= 1),
					$request{client_name},
					%request
				);
				$myresult[0] = ($res or ($Rules[$index]{$COMP_RHSBL_CNT} eq 'all')) ? ($myresult[0] + $res) : 0;
				$myresult[2] += $res if $res;
		};
		if ( exists($Rules[$index]{$COMP_RHSBL_KEY_SENDER}) ) {
				$res = compare_item(
					$COMP_RHSBL_KEY_SENDER,
					$Rules[$index]{$COMP_RHSBL_KEY_SENDER},
					($Rules[$index]{$COMP_RHSBL_CNT} ||= 1),
					$request{sender_domain},
					%request
				);
				$myresult[0] = ($res or ($Rules[$index]{$COMP_RHSBL_CNT} eq 'all')) ? ($myresult[0] + $res) : 0;
				$myresult[2] += $res if $res;
		};
		if ( exists($Rules[$index]{$COMP_RHSBL_KEY_HELO}) ) {
				$res = compare_item(
					$COMP_RHSBL_KEY_HELO,
					$Rules[$index]{$COMP_RHSBL_KEY_HELO},
					($Rules[$index]{$COMP_RHSBL_CNT} ||= 1),
					$request{helo_name},
					%request
				);
				$myresult[0] = ($res or ($Rules[$index]{$COMP_RHSBL_CNT} eq 'all')) ? ($myresult[0] + $res) : 0;
				$myresult[2] += $res if $res;
		};
		if ( exists($Rules[$index]{$COMP_RHSBL_KEY_RCLIENT}) ) {
				$res = compare_item(
					$COMP_RHSBL_KEY_RCLIENT,
					$Rules[$index]{$COMP_RHSBL_KEY_RCLIENT},
					($Rules[$index]{$COMP_RHSBL_CNT} ||= 1),
					$request{reverse_client_name},
					%request
				);
				$myresult[0] = ($res or ($Rules[$index]{$COMP_RHSBL_CNT} eq 'all')) ? ($myresult[0] + $res) : 0;
				$myresult[2] += $res if $res;
		};
	};
    };
    if ( wantsdebug (qw[ all ]) ) {
	$myline  = "[RULES]  RULE: ".$index."  MATCHES: ".((($myresult[0] - 2) > 0) ? ($myresult[0] - 2) : 0);
	$myline .= "  RBLCOUNT: ".$myresult[1] if $myresult[1];
	$myline .= "  RHSBLCOUNT: ".$myresult[2] if $myresult[2];
	$myline .= "  DNSBLTEXT: ".(join ("; ", @DNSBL_Text)) if ( (defined @DNSBL_Text) and (($myresult[1] > 0) or ($myresult[2] > 0)) );
	log_info ($myline);
    };
    return @myresult;
};


### SUB access policy

# access policy routine
sub smtpd_access_policy {
    my($parent,%request)		      		= @_;
    my($myaction)			      		= $postfwd_settings{default};
    my($index)				      		= 1;
    my($now)				      		= time();
    my($date)				      		= join(',', localtime($now));
    my($counters)					= "request=1".$postfwd_settings{sepreq}."interval=1";
    my($matched,$rblcnt,$rhlcnt,$t1,$t2,$t3,$stop)      = 0;
    my($mykey,$cacheid,$myline,$checkreq,$checkval,$var,$ratehit,$rateindex,$rulehits) = "";

    # save original request
    $request{orig} = hash_to_str (%request);

    # replace empty sender with <>
    $request{sender} = '<>' unless ($request{sender});

    # load postfwd_items attributes
    if ( my(%postfwd_items_attr) = postfwd_items (%request) ) {
	%request = (%request, %postfwd_items_attr);
    };

    # clear dnsbl timeout counters
    if ( $Cleanup_Timeouts and ($postfwd_settings{dns}{max_interval} > 0) and (($now - $Cleanup_Timeouts) > $postfwd_settings{dns}{max_interval}) ) {
	undef %Timeouts;
	log_info ("[CLEANUP] clearing dnsbl timeout counters") if wantsdebug (qw[ all verbose ]);
	$Cleanup_Timeouts = $now;
    };

    # wipe out old cache items
    if ( $Cleanup_Rates and ($postfwd_settings{rate}{cleanup} > 0) and (scalar keys %Rate_Cache > 0) and (($now - $Cleanup_Rates) > $postfwd_settings{rate}{cleanup}) ) {
	$t1 = time();
	$t3 = scalar keys %Rate_Cache;
	cleanup_rate_cache($now);
	$t2 = time();
	log_info ("[CLEANUP] cleaning rate-cache needed ".ts($t2 - $t1)
		." seconds for rate cleanup of "
		.($t3 - scalar keys %Rate_Cache)." out of ".$t3
		." cached items after cleanup time ".$postfwd_settings{rate}{cleanup}."s")
		if ( wantsdebug (qw[ all verbose rates cleanup childcleanup ]) or (($t2 - $t1) >= 1) );
	$Cleanup_Rates = $t1;
    };

    # increase rate limits
    if (@Rate_Items) {
	map { $checkval .= $_."=".$request{$_}.$postfwd_settings{seplst} if $request{$_} } (@Rate_Items);
	if ($checkval) {
		$checkval = "CMD=".$postfwd_commands{checkrate}.";TYPE=rate;ITEM=$checkval;SIZE=".($request{'size'} || 0).";RCPT=".($request{'recipient_count'} || 0);
			log_info ("[RATES] parent rate limit query: ".$checkval) if wantsdebug (qw[ all verbose rates ]);
			$checkval = cache_query ($checkval);
			log_info ("[RATES] parent rate limit answer: ".$checkval) if wantsdebug (qw[ all verbose rates ]);
			unless ($checkval eq '<undef>') {
				my($i,$r) = split $postfwd_settings{seplst}, $checkval;
				my($it, $ri) = split $postfwd_settings{seplim}, $i;
				if ($it and $ri and $r) {
					$ratehit = $it; $rateindex = $ri;
					%{$Rate_Cache{$it}{$ri}} = str_to_hash ($r);
					push @{$Rate_Cache{$it}{'list'}}, $ri;
					@{$Rate_Cache{$it}{'list'}} = uniq(@{$Rate_Cache{$it}{'list'}});
					$request{'ratecount'} = $Rate_Cache{$it}{$ri}{'count'};
				};
			};
	};
    };

    # Request cache enabled?
    if ( $postfwd_settings{request}{ttl} > 0 ) {

    	# construct cache identifier
	if ($postfwd_settings{cacheid}) {
		map { $cacheid .= $request{$_}.';' if (defined $request{$_}) } @{$postfwd_settings{cacheid}};
	} else {
		REQITEM: foreach $checkreq (sort keys %request) {
			next REQITEM unless $request{$checkreq};
			next REQITEM if ( ($checkreq eq "instance") or ($checkreq eq "queue_id") or ($checkreq eq "orig"));
			next REQITEM if ( $postfwd_settings{request}{no_size} and ($checkreq eq "size") );
			next REQITEM if ( $postfwd_settings{request}{no_sender} and ($checkreq eq "sender") );
			if ( $postfwd_settings{request}{rdomain_only} and ($checkreq eq "recipient") ) {
				$cacheid .= $request{recipient_domain}.';';
			} else {
				$cacheid .= $request{$checkreq}.';';
			};
		};
	};
	log_info ("created cache-id: $cacheid") if wantsdebug (qw[ all ]);

    	# wipe out old cache entries
	if ( $Cleanup_Requests and (scalar keys %Request_Cache > 0) and (($now - $Cleanup_Requests) > $postfwd_settings{request}{cleanup}) ) {
		$t1 = time();
		$t3 = scalar keys %Request_Cache;
		cleanup_request_cache($now);
		$t2 = time();
		log_info ("[CLEANUP] cleaning request-cache needed ".ts($t2 - $t1)
			." seconds for request cleanup of "
			.($t3 - scalar keys %Request_Cache)." out of ".$t3
			." cached items after cleanup time ".$postfwd_settings{request}{cleanup}."s")
			if ( wantsdebug (qw[ all verbose cleanup childcleanup ]) or (($t2 - $t1) >= 1) );
		$Cleanup_Requests = $t1;
	};
    };

    # check rate
    if ( $ratehit and $rateindex and defined $Rate_Cache{$ratehit}{$rateindex} ) {

	$counters .= $postfwd_settings{sepreq}."rate=1";
	$Matches{$Rate_Cache{$ratehit}{$rateindex}{rule}}++;
	$myaction = $Rate_Cache{$ratehit}{$rateindex}{action};
	# substitute check for $$vars in action
	$myaction = $var if ( $var = devar_item ("==",$myaction,"action",%request) );
	log_info ("[RATES] rule=".$Rule_by_ID{$Rate_Cache{$ratehit}{$rateindex}{rule}}
		. ", id=".$Rate_Cache{$ratehit}{$rateindex}{rule}
		. ( ($request{queue_id}) ? ", queue=".$request{queue_id} : '' )
		. ", client=".$request{client_name}."[".$request{client_address}."]"
		. ", sender=<".(($request{sender} eq '<>') ? "" : $request{sender}).">"
		. ( ($request{recipient}) ? ", recipient=<".$request{recipient}.">" : '' )
		. ", helo=<".$request{helo_name}.">"
		. ", proto=".$request{protocol_name}
		. ", state=".$request{protocol_state}
		. ", delay=".ts(time() - $now)."s"
		. ", action=".$myaction." (item: '".$ratehit."'"
		. ", type: ".$Rate_Cache{$ratehit}{$rateindex}{type}
		. ", count: ".$Rate_Cache{$ratehit}{$rateindex}{count}."/".$Rate_Cache{$ratehit}{$rateindex}{maxcount}
		. ", time: ".ts($now - $Rate_Cache{$ratehit}{$rateindex}{"time"})."/".$Rate_Cache{$ratehit}{$rateindex}{ttl}."s)"
		) unless $postfwd_settings{request}{nolog};

    # check own cache
    } elsif ( ($postfwd_settings{request}{ttl} > 0)
	and ((exists($Request_Cache{$cacheid}{$COMP_ACTION})) and ($now <= $Request_Cache{$cacheid}{'until'})) ) {
	$counters .= $postfwd_settings{sepreq}."ccache=1";
	$myaction = $Request_Cache{$cacheid}{$COMP_ACTION};
	if ( $Request_Cache{$cacheid}{hit} ) {
		$Matches{$Request_Cache{$cacheid}{$COMP_ID}}++;
		$rulehits = join $postfwd_settings{sepreq}, (split ';', $Request_Cache{$cacheid}{hits}) if $Request_Cache{$cacheid}{hits};
		log_info ("[CACHE] rule=".$Rule_by_ID{$Request_Cache{$cacheid}{$COMP_ID}}
			. ", id=".$Request_Cache{$cacheid}{$COMP_ID}
			. ( ($request{queue_id}) ? ", queue=".$request{queue_id} : '' )
			. ", client=".$request{client_name}."[".$request{client_address}."]"
			. ", sender=<".(($request{sender} eq '<>') ? "" : $request{sender}).">"
			. ( ($request{recipient}) ? ", recipient=<".$request{recipient}.">" : '' )
			. ", helo=<".$request{helo_name}.">"
			. ", proto=".$request{protocol_name}
			. ", state=".$request{protocol_state}
			. ", delay=".ts(time() - $now)."s"
			. ", hits=".$Request_Cache{$cacheid}{hits}
			. ", action=".$Request_Cache{$cacheid}{$COMP_ACTION}
			) unless $postfwd_settings{request}{nolog};
	};

    # check parent cache
    } elsif ( ($postfwd_settings{request}{ttl} > 0)
	and not($postfwd_settings{request}{noparent})
	and not((my $pans = cache_query ("CMD=".$postfwd_commands{getcacheitem}.";TYPE=request;ITEM=$cacheid")) eq '<undef>') ) {
	map { $Request_Cache{$cacheid}{$1} = $2 if m/$postfwd_patterns{keyval}/ } (split $postfwd_settings{sepreq}, $pans);
	$counters .= $postfwd_settings{sepreq}."pcache=1";
	$myaction = $Request_Cache{$cacheid}{$COMP_ACTION};
	if ( $Request_Cache{$cacheid}{hit} ) {
		$Matches{$Request_Cache{$cacheid}{$COMP_ID}}++;
		$rulehits = join $postfwd_settings{sepreq}, (split ';', $Request_Cache{$cacheid}{hits}) if $Request_Cache{$cacheid}{hits};
		log_info ("[CACHE] rule=".$Rule_by_ID{$Request_Cache{$cacheid}{$COMP_ID}}
			. ", id=".$Request_Cache{$cacheid}{$COMP_ID}
			. ( ($request{queue_id}) ? ", queue=".$request{queue_id} : '' )
			. ", client=".$request{client_name}."[".$request{client_address}."]"
			. ", sender=<".(($request{sender} eq '<>') ? "" : $request{sender}).">"
			. ( ($request{recipient}) ? ", recipient=<".$request{recipient}.">" : '' )
			. ", helo=<".$request{helo_name}.">"
			. ", proto=".$request{protocol_name}
			. ", state=".$request{protocol_state}
			. ", delay=".ts(time() - $now)."s"
			. ", hits=".$Request_Cache{$cacheid}{hits}
			. ", action=".$Request_Cache{$cacheid}{$COMP_ACTION}
			) unless $postfwd_settings{request}{nolog};
	};

    # check rules
    } else {

	# refresh config if '-I' was set
	read_config(0) if $postfwd_settings{instant};

	if ($#Rules < 0) {
		log_note("critical: no rules found - i feel useless (have you set -f or -r?)");

	} else {

		# clean up rbl cache
		if ( not($postfwd_settings{dns}{disabled}) and (scalar keys %DNS_Cache > 0) and (($now - $Cleanup_RBLs) > $postfwd_settings{dns}{cleanup}) ) {
			$t1 = time();
			$t3 = scalar keys %DNS_Cache;
			cleanup_dns_cache($now);
			$t2 = time();
			log_info ("[CLEANUP] cleaning dns-cache needed ".ts($t2 - $t1)
				." seconds for rbl cleanup of "
				.($t3 - scalar keys %DNS_Cache)." out of ".$t3
				." cached items after cleanup time ".$postfwd_settings{dns}{cleanup}."s")
				if ( wantsdebug (qw[ all verbose cleanup childcleanup ]) or (($t2 - $t1) >= 1) );
			$Cleanup_RBLs = $t1;
		};

		# prepares hit counters
		$request{$COMP_MATCHES}   = 0;
		$request{$COMP_RBL_CNT}   = 0;
		$request{$COMP_RHSBL_CNT} = 0;

		RULE: for ($index=0;$index<=$#Rules;$index++) {

			# compare request against rule
			next unless exists $Rules[$index];
			($matched,$rblcnt,$rhlcnt,my $compcnt) = compare_rule ($index, $date, %request);

			# enables/overrides hit counters for later use
			$request{$COMP_MATCHES}    = $matched;
			$request{$COMP_RBL_CNT}    = $rblcnt;
			$request{$COMP_RHSBL_CNT}  = $rhlcnt;
			$counters .= $postfwd_settings{sepreq}.$compcnt if $compcnt;

			# matched? prepare logline, increase counters
			if ($matched > 0) {
				$myaction = $Rules[$index]{$COMP_ACTION};
				$Matches{$Rules[$index]{$COMP_ID}}++;
				$rulehits .= $postfwd_settings{sepreq} if $rulehits;
				$rulehits .= $Rules[$index]{$COMP_ID};
				$request{$COMP_HITS} .= ';' if (defined $request{$COMP_HITS});
				$request{$COMP_HITS} .= $Rules[$index]{$COMP_ID};
				# substitute check for $$vars in action
				$myaction = $var if ( $var = devar_item ("==",$myaction,"action",%request) );
				$myline = "rule=".$index
					. ", id=".$Rules[$index]{$COMP_ID}
					. ( ($request{queue_id}) ? ", queue=".$request{queue_id} : '' )
					. ", client=".$request{client_name}."[".$request{client_address}."]"
					. ", sender=<".(($request{sender} eq '<>') ? "" : $request{sender}).">"
					. ( ($request{recipient}) ? ", recipient=<".$request{recipient}.">" : '' )
					. ", helo=<".$request{helo_name}.">"
					. ", proto=".$request{protocol_name}
					. ", state=".$request{protocol_state};

				# check for postfwd action
				if ($myaction =~ /^(\w[\-\w]+)\s*\(\s*(.*?)\s*\)$/) {
					my($mycmd,$myarg) = ($1, $2);
					if (defined $postfwd_actions{$mycmd}) {
						log_info ("[PLUGIN] executing postfwd-action $mycmd") if wantsdebug (qw[ all ]);
						($stop, $index, $myaction, $myline, %request) = &{$postfwd_actions{$mycmd}}($index, $now, $mycmd, $myarg, $myline, %request);
						# substitute again after postfwd-actions
						$myaction = $var if ( $var = devar_item ("==",$myaction,"action",%request) );
					} else {
						log_warn ("[RULES] ".$myline." - error: unknown command \"".$1."\" - ignoring");
						$myaction = $postfwd_settings{default};
					};
				# normal rule. returns $action.
				} else { $stop = 1; };
				if ($stop) {
					$myline .= ", delay=".ts(time() - $now)."s, hits=".$request{$COMP_HITS}.", action=".$myaction;
    					log_info ("[RULES] ".$myline) unless $postfwd_settings{request}{nolog};
					$counters .= $postfwd_settings{sepreq}."ruleset=1";
					# update cache
					if ( $postfwd_settings{request}{ttl} > 0 ) {
						$Request_Cache{$cacheid}{ttl}		    = ($Rules[$index]{$COMP_CACHE} || $postfwd_settings{request}{ttl});
						$Request_Cache{$cacheid}{'until'}	    = $now + $Request_Cache{$cacheid}{ttl};
						$Request_Cache{$cacheid}{$COMP_ACTION}	    = $myaction;
						$Request_Cache{$cacheid}{$COMP_ID}    	    = $Rules[$index]{$COMP_ID};
						$Request_Cache{$cacheid}{hit}	    	    = $matched;
						$Request_Cache{$cacheid}{hits}		    = $request{$COMP_HITS};
						cache_query ("CMD=".$postfwd_commands{setcacheitem}.";TYPE=request;ITEM=$cacheid".hash_to_str(%{$Request_Cache{$cacheid}}))
							unless ($postfwd_settings{request}{noparent});
					};
					last RULE;
				};
			} else { undef $myline; };
		};
	};
    };
    # increase counters and return action
    if ($postfwd_settings{summary} and defined $parent) {
	print $parent "CMD=".$postfwd_commands{countcache}.";TYPE=$counters"
	   .(($rulehits) ? $postfwd_settings{seplst}."CMD=".$postfwd_commands{matchcache}.";TYPE=$rulehits" : "")
	   ."\n"; $parent->getline();
    };
    $myaction = $postfwd_settings{default} if ($postfwd_settings{test} or !($myaction));
    map { &{$postfwd_settings{syslog}{logger}} ('info', "  %$_") } hash_to_list ('Request_Cache', %Request_Cache)	if wantsdebug (qw[ child_cache child_request_cache ]);
    map { &{$postfwd_settings{syslog}{logger}} ('info', "  %$_") } hash_to_list ('Rate_Cache', %Rate_Cache)		if wantsdebug (qw[ child_cache child_rate_cache ]);
    map { &{$postfwd_settings{syslog}{logger}} ('info', "  %$_") } hash_to_list ('DNS_Cache', %DNS_Cache)		if wantsdebug (qw[ child_cache child_dns_cache ]);
    return $myaction;
};


## Net::Server::PreFork methods

# ignore syslog failures
sub handle_syslog_error {};

# reload config on HUP signal
sub sig_hup {
	my $self = shift;
	log_note ("catched HUP signal - reloading ruleset on next request");
	read_config(1);
	map { kill ("HUP", $_) } (keys %{$self->{server}->{children}});
};

# parent start
sub pre_loop_hook {
	my $self = shift;
	# change parent's name
	$0 = $self->{server}->{commandline} = " ".$postfwd_settings{name}.'::policy';
	$self->{server}->{syslog_ident} = $postfwd_settings{name}."/policy";
	$StartTime = $Summary = $Cleanup_Timeouts = $Cleanup_Requests = $Cleanup_RBLs = $Cleanup_Rates = time();
	init_log ($self->{server}->{syslog_ident});
	# load plugin-items
	get_plugins (@{$postfwd_settings{Plugins}}) if $postfwd_settings{Plugins};
	# read configuration
	read_config(1);
	log_info ("ready for input");
};

# increase counters
sub count_cache { map { $Count{$1} += $2 if m/$postfwd_patterns{cntval}/ } (split ($postfwd_settings{sepreq}, $_[1])) if $_[1] };

# increase matches
sub match_cache { map { $Hits{$_}++ } (split ($postfwd_settings{sepreq}, $_[1])) if $_[1] };

# program usage statistics
sub list_stats {
	my $now     = time();
	my $uptime  = $now - $StartTime;
	my @output  =();
	return @output unless $uptime and $Count{request};

	# averages, hitrates and counters
	map { $Count{$_} ||= 0 } qw(ruleset interval top rate pcache ccache dnsqueries dnstimeouts dnsinterval dnstop);
	my $lastreq = (($now - $Summary) > 0) ? $Count{interval} / ($now - $Summary) * 60 : 0;
	my $lastdns = (($now - $Summary) > 0) ? $Count{dnsinterval} / ($now - $Summary) * 60 : 0;
	$Count{top} = $lastreq if $lastreq > $Count{top};
	$Count{dnstop} = $lastdns if $lastdns > $Count{dnstop};
	my $dnstimeoutrate = ($Count{dnsqueries}) ? $Count{dnstimeouts} / $Count{dnsqueries} * 100 : 0;

	# log program  statistics
	if ( not($postfwd_settings{syslog}{noidlestats}) or ($Count{interval} > 0) ) {
		push ( @output, sprintf (
			"[STATS] %s::policy %s: %d requests since %d days, %02d:%02d:%02d hours",
			$postfwd_settings{name},
			$postfwd_settings{version},
			$Count{request},
			($uptime / 60 / 60 / 24),
			(($uptime / 60 / 60) % 24),
			(($uptime / 60) % 60),
			($uptime % 60)
		) );

		push ( @output, sprintf (
			"[STATS] Requests: %.2f/min last, %.2f/min overall, %.2f/min top",
			$lastreq,
			($uptime) ? $Count{request} / $uptime * 60 : 0,
			$Count{top}
		) );

		push ( @output, sprintf (
			"[STATS] Dnsstats: %.2f/min last, %.2f/min overall, %.2f/min top",
			$lastdns,
			($uptime) ? $Count{dnsqueries} / $uptime * 60 : 0,
			$Count{dnstop}
		) ) unless ($postfwd_settings{dns}{disable});

		push ( @output, sprintf (
			"[STATS] Hitrates: %.1f%% ruleset, %.1f%% parent, %.1f%% child, %.1f%% rates",
			($Count{request}) ? $Count{ruleset} / $Count{request} * 100 : 0,
			($Count{request}) ? $Count{pcache} / $Count{request} * 100 : 0,
			($Count{request}) ? $Count{ccache} / $Count{request} * 100 : 0,
			($Count{request}) ? $Count{rate} / $Count{request} * 100 : 0
		) );

		push ( @output, sprintf (
			"[STATS] Timeouts: %.1f%% (%d of %d dns queries)",
			$dnstimeoutrate,
			$Count{dnstimeouts},
			$Count{dnsqueries}
		) ) unless ($postfwd_settings{dns}{disable});

		# per rule stats
		if (%Hits and not($postfwd_settings{syslog}{norulestats})) {
			my @rulecharts = (sort { ($Hits{$b} || 0) <=> ($Hits{$a} || 0) } (keys %Hits)); my $cntln = length(($Hits{$rulecharts[0]} || 2)) + 2;
			map { push ( @output, sprintf ("[STATS] %".$cntln."d matches for id:  %s", ($Hits{$_} || 0), $_)) } @rulecharts;
		};
	};

	$Count{interval} = $Count{dnsinterval} = 0;
	$Summary = $now;
	return @output;
};

# parent processes child input
sub child_is_talking_hook {
    my($self,$sock) = @_;
    my $answer = "\n";
    my $msg = $sock->getline();
    # during tests it turned out that children
    # send empty messages in some situations
    if (defined $msg) {
	log_info ("child said '$msg'") if wantsdebug (qw[ all ]);
	if ($msg =~ m/$postfwd_patterns{command}/) {
	    foreach (split $postfwd_settings{seplst}, $msg) {
		if (m/$postfwd_patterns{countcache}/) {
		    $self->count_cache($1);
		} elsif (m/$postfwd_patterns{matchcache}/) {
		    $self->match_cache($1);
		} elsif (m/$postfwd_patterns{dumpstats}/) {
		    $answer = (join $postfwd_settings{sepreq}.$postfwd_settings{seplst}, list_stats())."\n";
		} else {
		    log_note ("warning: child sent unknown command '$_'");
		};
	    };
	} else {
	    log_note ("warning: child sent unknown message '$msg'");
	};
    };
    print $sock "$answer";
};

# child start
sub child_init_hook {
	my $self = shift;
	# change children's names
	$0 = $self->{server}->{commandline} = " ".$postfwd_settings{name}.'::policy::child';
	log_info ("ready for input") if wantsdebug (qw[ all verbose ]);
};

# child process request
sub process_request {
	my($self) = shift;
	my($client) = $self->{server}->{client};
	my($parent) = $self->{server}->{parent_sock};
	my(%attr) = ();
	while (<STDIN>) {
		s/\r?\n$//;
		# respond to masters ping
		if ($_ eq $postfwd_patterns{ping}) {
			$client->print("$postfwd_patterns{pong}\n");
		} elsif (m/$postfwd_patterns{dumpstats}/) {
			$parent->print("$_\n");
			$client->print($parent->getline()."\n");
		# process input
		} else {
			process_input ($parent, $client, $_, \%attr);
		};
	};
};

# process delegation protocol input
sub process_input {
	my($parent,$client,$msg,$attr) = @_;
	# remember argument=value
	if ( $msg =~ /^([^=]{1,512})=(.{0,512})/ ) {
		$$attr{$1} = $2;
	# evaluate request
	} elsif ( $msg eq '' ) {
		map { log_info ("Attribute: $_=$$attr{$_}") } (keys %$attr) if wantsdebug (qw[ all request ]);
		unless ( (defined $$attr{request}) and ($$attr{request} eq "smtpd_access_policy") ) {
			log_note ("Ignoring unrecognized request type: '".((defined $$attr{request}) ? substr($$attr{request},0,100) : '')."'");
		} else {
			my $action = smtpd_access_policy($parent, %$attr) || $postfwd_settings{default};
			log_info ("Action: $action") if wantsdebug (qw[ all verbose ]);
			if ($client) {
				print $client ("action=$action\n\n");
			} else {
				print STDOUT ("action=$action\n\n");
			};
			%$attr = ();
		};
	# unknown command
	} else {
		log_note ("Ignoring garbage '".substr($msg, 0, 100)."'");
	};
};

1; # EOF postfwd2::server


use warnings;
use strict;
use Getopt::Long 2.25 qw(:config no_ignore_case bundling);
use Pod::Usage;
# master daemon
use Net::Server::Daemonize qw(daemonize);
# own modules
# program settings, syslogging
import postfwd2::basic qw(:DEFAULT %postfwd_commands &check_inet &check_unix &wantsdebug &hash_to_list $TIMEHIRES);
# cache daemon (requests, dns, limits), Net::Server::Multiplex
import postfwd2::cache qw();
# policy daemon, Net::Server::PreFork 
import postfwd2::server qw(&read_config &show_config &process_input &get_plugins);


# functions to start, override with '--daemons' at command line
my @daemons = qw[ cache server ];

use vars qw(
	%options %children %failures
);

# parse command-line
my $Commandline = "$0 ".(join ' ', @ARGV);
GetOptions( \%options,
	# Ruleset
	'rule|r=s'		  => sub{ my($opt,$value) = @_; push (@{$postfwd_settings{Configs}}, $opt.$postfwd_settings{sepreq}.$value) },
	'file|f=s'		  => sub{ my($opt,$value) = @_; push (@{$postfwd_settings{Configs}}, $opt.$postfwd_settings{sepreq}.$value) },
	'scores|score|s=s%'	  => \%{$postfwd_settings{scores}},
        "test|t"		  => \$postfwd_settings{test},
        "instantcfg|I"		  => \$postfwd_settings{instant},
	"config_timeout=i"	  => \$postfwd_settings{timeout}{config},
	"showconfig|C",
	"defaults|settings|D",
	# Networking
	"umask=s"		  => \$postfwd_settings{base}{umask},
	"user|u=s"		  => \$postfwd_settings{base}{user},
	"group|g=s"		  => \$postfwd_settings{base}{group},
	"server_socket|socket=s"  => sub{ ($postfwd_settings{server}{proto}, $postfwd_settings{server}{host}, $postfwd_settings{server}{port}) = (split ':', $_[1]) },
	"interface|i=s"		  => \$postfwd_settings{server}{host},
	"port|p=s"		  => \$postfwd_settings{server}{port},
	"proto=s"		  => \$postfwd_settings{server}{proto},
	"server_umask=s"	  => \$postfwd_settings{server}{umask},
	"min_servers=i"	 	  => \$postfwd_settings{server}{min_servers},
	"max_servers=i"	 	  => \$postfwd_settings{server}{max_servers},
	"min_spare_servers=i"	  => \$postfwd_settings{server}{min_spare_servers},
	"max_spare_servers=i"	  => \$postfwd_settings{server}{max_spare_servers},
        "nodns|n"		  => \$postfwd_settings{dns}{disabled},
	"dns_timeout=i"		  => \$postfwd_settings{dns}{timeout},
	"dns_async_txt"		  => \$postfwd_settings{dns}{async_txt},
	"dns_timeout_max=i"	  => \$postfwd_settings{dns}{max_timeout},
	"dns_timeout_interval=i"  => \$postfwd_settings{dns}{max_interval},
	"dns_max_ns_lookups=i"	  => \$postfwd_settings{dns}{max_ns_lookups},
	"dns_max_mx_lookups=i"	  => \$postfwd_settings{dns}{max_mx_lookups},
	"cache-rbl-timeout=i"	  => \$postfwd_settings{dns}{ttl},
	"cache-rbl-default=s"	  => \$postfwd_settings{dns}{mask},
	"cleanup-rbls=i"	  => \$postfwd_settings{dns}{cleanup},
	"no_parent_dns_cache"	  => \$postfwd_settings{dns}{noparent},
	"parent_dns_cache"	  => sub { $postfwd_settings{dns}{noparent} = 0 },
	# Stats
	"summary|stats|S=i"	  => \$postfwd_settings{summary},
	"norulestats"		  => \$postfwd_settings{syslog}{norulestats},
	"no-rulestats"		  => \$postfwd_settings{syslog}{norulestats},
	"noidlestats"		  => \$postfwd_settings{syslog}{noidlestats},
	"no-idlestats"		  => \$postfwd_settings{syslog}{noidlestats},
	"stdoutlog|stdout|L"	  => \$postfwd_settings{syslog}{stdout},
	# Cache
	"cache_socket=s"	  => sub{ ($postfwd_settings{cache}{proto}, $postfwd_settings{cache}{host}, $postfwd_settings{cache}{port}) = (split ':', $_[1]) },
	"cache_interface=s"	  => \$postfwd_settings{cache}{host},
	"cache_port=s"		  => \$postfwd_settings{cache}{port},
	"cache_proto=s"		  => \$postfwd_settings{cache}{proto},
	"cache_umask=s"		  => \$postfwd_settings{server}{umask},
	"cache|c=i"		  => \$postfwd_settings{request}{ttl},
	"cacheid=s"		  => sub { push @{$postfwd_settings{cacheid}}, (split /[,\s]+/, $_[1]) },
	"cache-rdomain-only"	  => \$postfwd_settings{request}{rdomain_only},
	"cache-no-sender"	  => \$postfwd_settings{request}{no_sender},
	"cache-no-size"		  => \$postfwd_settings{request}{no_size},
	"cleanup-requests=i"	  => \$postfwd_settings{request}{cleanup},
	"no_parent_request_cache" => \$postfwd_settings{request}{noparent},
	"no_parent_rate_cache"    => \$postfwd_settings{rate}{noparent},
	"no_parent_cache"         => sub{ $postfwd_settings{request}{noparent} = $postfwd_settings{rate}{noparent} = $postfwd_settings{dns}{noparent} = 1 },
	# Limits
	"cleanup-rates=i"	  => \$postfwd_settings{rate}{cleanup},
	"keep_rates|keep_limits|keep_rates_on_reload" => \$postfwd_settings{keep_rates},
	# Control
	'version|V'		  => sub{ print "$postfwd_settings{name} $postfwd_settings{version} (Net::DNS ".(Net::DNS->VERSION || '<undef>').", Net::Server ".(Net::Server->VERSION || '<undef>').", Sys::Syslog ".($Sys::Syslog::VERSION || '<undef>').", ".(($TIMEHIRES) ? "Time::HiRes $TIMEHIRES, " : '')."Perl ".$]." on ".$^O.")\n"; exit 1; },
	'versionshort|shortversion' => sub{ print "$postfwd_settings{version}\n"; exit 1; },
	'manual|m'		  => sub{ # contructing command string (de-tainting $0)
                                          $postfwd_settings{manual} .= ($0 =~ /^([-\@\/\w. ]+)$/) ? " \"".$1 : " \"".$postfwd_settings{name};
                                          $postfwd_settings{manual} .= "\" | ".$postfwd_settings{pager};
                                          system ($postfwd_settings{manual}); exit 1; },
        "term|kill|stop|k",
        "hup|reload",
        "dumpcache",
        "dumpstats",
        "pid|pidfile|pid_file=s"  => \$postfwd_settings{master}{pid_file},
        "watchdog=i"		  => \$postfwd_settings{master}{watchdog},
        "respawn=i"		  => \$postfwd_settings{master}{respawn},
        "failures=i"		  => \$postfwd_settings{master}{failures},
	"daemon|d!"		  => \$postfwd_settings{daemon},
	"daemons=s"		  => sub { push @{$options{daemons}}, (split /[,\s]+/, $_[1]) },
	# Logging
        "debug=s"		  => sub { push @{$options{debug}}, (split /[,\s]+/, $_[1]) },
        "verbose|v+"		  => \$postfwd_settings{verbose},
	"logname|l=s"		  => sub{ $postfwd_settings{name}		= $_[1];
				     $postfwd_settings{cache}{syslog_ident}	= $_[1].'/cache';
				     $postfwd_settings{server}{syslog_ident}	= $_[1].'/policy'; },
	"facility=s"		  => \$postfwd_settings{syslog}{facility},
	"socktype=s"		  => \$postfwd_settings{syslog}{socktype},
	"nodnslog"		  => \$postfwd_settings{dns}{nolog},
	"no-dnslog"		  => \$postfwd_settings{dns}{nolog},
	"anydnslog"		  => \$postfwd_settings{dns}{anylog},
	"norulelog"		  => \$postfwd_settings{request}{nolog},
	"no-rulelog"		  => \$postfwd_settings{request}{nolog},
	"perfmon|P"		  => \$postfwd_settings{syslog}{nolog},
	"plugins=s"		  => sub { push @{$postfwd_settings{Plugins}}, $_[1] },

	# Unused
	"start",
	"chroot|R=s",
	"shortlog",
	"dns_queuesize=i",
	"dns_retries=i",
) or pod2usage (-msg => "\nPlease see \"".$postfwd_settings{name}." -m\" for detailed instructions.\n", -verbose => 1);

map { $postfwd_settings{syslog}{stdout} = 1 if defined $options{$_} } qw(term hup showconfig dumpcache dumpstats defaults);

# basic syntax checks
if ($postfwd_settings{verbose} > 1) {
	$postfwd_settings{debug}{all} = 1;
} elsif ($postfwd_settings{verbose}) {
	$postfwd_settings{debug}{verbose} = 1;
};
map { $postfwd_settings{debug}{$_} = 1 } uniq(@{$options{debug}});
map { $postfwd_settings{daemons}{$_} = 1 } ((defined $options{daemons}) ? uniq(@{$options{daemons}}) : uniq(@daemons));
map { $postfwd_settings{$_}{check} = ($postfwd_settings{$_}{proto} eq 'unix') ? \&check_unix : \&check_inet } @daemons;

# terminate at -k or --kill
if (defined $options{'term'}) {
	kill "TERM", get_master_pid();
	exit (0);
# reload at --reload
} elsif (defined $options{'hup'}) {
	kill "HUP", get_master_pid();
	exit (0);
};

# init_log
init_log ($postfwd_settings{name}."/master");

# read and display configuration
if (defined $options{'showconfig'}) {
	read_config(1);
        show_config();
        exit 1;
};

# show program settings
if (defined $options{'defaults'}) {
	print "\n"; map { print "  %$_\n" } hash_to_list ('postfwd_settings', %postfwd_settings);
	if (wantsdebug (qw[ all verbose ])) {
		map { print "  %$_\n" } hash_to_list ('postfwd_commands', %postfwd_commands);
		map { print "  %$_\n" } hash_to_list ('postfwd_patterns', %postfwd_patterns);
	};
	print "\n"; exit 1;
};

# dump stats
if (defined $options{'dumpstats'}) {
	foreach my $daemon (sort keys %{$postfwd_settings{daemons}}) {
		print "\n";
		map { print ("$_\n") } get_stats ($daemon);
	};
	print "\n";
	exit 1;
};

# dump cache contents
if (defined $options{'dumpcache'}) {
	print "\n".( join "\n",
		split $postfwd_settings{sepreq}.$postfwd_settings{seplst},
			(&{$postfwd_settings{cache}{check}} ('cache', 'CMD=DC;') || '<undef>')
	)."\n\n";
	exit 1;
};

# de-taint command-line
%postfwd_settings = detaint_hash (%postfwd_settings);

# check for --nodaemon option
unless ($postfwd_settings{daemon}) {
	my(%attr) = ();
	get_plugins (@{$postfwd_settings{Plugins}}) if $postfwd_settings{Plugins};
	read_config(1);
	map { $postfwd_settings{daemons}{$_} = 0 } (keys %{$postfwd_settings{daemons}});
	$postfwd_settings{request}{noparent} = $postfwd_settings{rate}{noparent} = $postfwd_settings{dns}{noparent} = 1;
	while (<>) {
		chomp;
		process_input (undef, undef, $_, \%attr);
	};
	exit;
};

# daemonize master
log_info ($postfwd_settings{name}." "
	.$postfwd_settings{version}." starting"
	.((scalar keys %{$postfwd_settings{debug}}) ? " with debug levels: ".(join ',', keys %{$postfwd_settings{debug}}) : ''));
log_info ("Net::DNS ".(Net::DNS->VERSION || '<undef>').", Net::Server ".(Net::Server->VERSION || '<undef>').", Sys::Syslog ".($Sys::Syslog::VERSION || '<undef>').", ".(($TIMEHIRES) ? "Time::HiRes $TIMEHIRES, " : '')."Perl ".$]." on ".$^O) if wantsdebug (qw[ all verbose ]);
umask oct($postfwd_settings{base}{umask});
daemonize($postfwd_settings{base}{user}, $postfwd_settings{base}{group}, $postfwd_settings{master}{pid_file});
$0 = $Commandline;

# prepare shared SIG handlers
$SIG{__WARN__} = sub { log_warn("warning: $_[0]") };
$SIG{__DIE__}  = sub { log_crit("FATAL: $_[0]"); die @_; };

# fork daemons: cache and server
foreach my $daemon (sort keys %{$postfwd_settings{daemons}}) {
	umask oct($postfwd_settings{$daemon}{umask});
	if (my $pid = spawn_daemon ($daemon)) {
		log_info ("Started $daemon at pid $pid");
		$children{$daemon} = $pid;
	};
};
umask oct($postfwd_settings{base}{umask});

# prepare master SIG handlers and enter main loop
$SIG{TERM} = sub { end_program(); };
$SIG{HUP} = sub { reload_program(); };
if ($postfwd_settings{summary}) {
	$SIG{ALRM} = sub {
		log_stats();
		alarm ($postfwd_settings{summary})
	};
	alarm ($postfwd_settings{summary});
};

while (1) {
	# check daemons every <watchdog> seconds
	if ($postfwd_settings{master}{watchdog}) {
		sleep ($postfwd_settings{master}{watchdog});
		foreach my $daemon (sort keys %{$postfwd_settings{daemons}}) {
			if (check_daemon ($daemon)) {
				$failures{$daemon} = 0;
			} else {
				if (++$failures{$daemon} >= $postfwd_settings{master}{failures}) {
					# terminate program
					log_crit ("$daemon-daemon check failed $failures{$daemon} times - terminating program");
					end_program();
				} else {
					# restart daemon
					log_crit ("$daemon-daemon check failed $failures{$daemon} times - respawning in ".$postfwd_settings{master}{respawn}." seconds");
					kill 15, $children{$daemon}; sleep $postfwd_settings{master}{respawn};
					if (my $pid = spawn_daemon ($daemon)) {
						log_info ("Started $daemon at pid $pid");
						$children{$daemon} = $pid;
					};
				};
			};
		};
	# no watchdog -> sleep until signal
	} else {
		sleep;
	};
};
die "master-daemon: should never see me!\n";


## SUBS

# cleanup children and files and terminate
sub end_program {
	local $SIG{TERM} = 'IGNORE';
	if ($postfwd_settings{summary}) {
		undef $postfwd_settings{syslog}{noidlestats};
		log_stats();
	};
	log_note ($postfwd_settings{name}." ".$postfwd_settings{version}." terminating...");
	unlink $postfwd_settings{master}{pid_file} if (-T $postfwd_settings{master}{pid_file});
	# negative signal no. kills the whole process group
	kill -15, $$;
	exit (0);
};

# send hup to child processes
sub reload_program {
	log_note ($postfwd_settings{name}." ".$postfwd_settings{version}." reloading...");
	map { kill 1, $_ } (values %children) if %children;
};

# check a cache or server daemon
sub check_daemon { return ((&{$postfwd_settings{$_[0]}{check}}($_[0],$postfwd_patterns{ping}) || '') eq $postfwd_patterns{pong}) };

# spawn a cache or server daemon
sub spawn_daemon {
	my ($type) = @_;
	my $pid = fork();
	die "Can not fork $type: $!\n" unless defined $pid;
	if ($pid == 0) {
		my %service =  %{$postfwd_settings{$type}};
		# Net::Server dies when a unix domain socket without dot "." is used
		$service{port} .= '|unix' if (($service{proto} eq 'unix') and not($service{port} =~ /\|unix$/));
		my %daemonopts = (%{$postfwd_settings{base}}, %service);
		my $daemon = bless { server => { %daemonopts } }, "postfwd2::$type";
		$daemon->run();
		die "$type-daemon: should never see me!\n";
	};
	return $pid;
};

# get pid of running master process
sub get_master_pid {
	(-e $postfwd_settings{master}{pid_file}) or die $postfwd_settings{name}.": Can not find pid_file ".$postfwd_settings{master}{pid_file}.": $!\n";
	(-T $postfwd_settings{master}{pid_file}) or die $postfwd_settings{name}.": Can not open pid_file ".$postfwd_settings{master}{pid_file}.": not a textfile\n";
	open PIDFILE, "<".$postfwd_settings{master}{pid_file} or die $postfwd_settings{name}.": Can open pid_file ".$postfwd_settings{master}{pid_file}.": $!\n";
	my $pid = <PIDFILE>;
	($pid =~ m/^(\d+)$/) or die $postfwd_settings{name}.": Invalid pid_file content '$pid' (pid_file ".$postfwd_settings{master}{pid_file}.")\n";
	return $1;
};

# detaints postfwd2 settings
sub detaint_hash {
	my (%request) = @_;
	# cycle through key=value pairs
	while ( my($s, $v) = each %request ) {
		my $r = ref $v;
		# type hash: recursively call ourself
		if ($r eq 'HASH') {
			%{$v} = detaint_hash ( %{$v} );
		# type array: detaint whole list
		} elsif ($r eq 'ARRAY') {
			@{$request{$s}} = map { $_ = (($_ =~ m/^(.*)$/) ? $1 : $_ ) if $_ } @{$v};
		# type scalar: detaint argument
		} elsif ($r eq '') {
			$request{$s} = (($v =~ m/^(.*)$/) ? $1 : $v) if ($s and $v);
		};
	};
	return %request;
};

# send stats to syslog
sub log_stats { map { &{$postfwd_settings{syslog}{logger}} ('notice', "$_") unless ($_ eq '<undef>') } get_stats(sort keys %{$postfwd_settings{daemons}}); };

# retrieve status from children
sub get_stats {
	my @daemons = @_; my @output = ();
	map { push @output, (split $postfwd_settings{sepreq}.$postfwd_settings{seplst}, (&{$postfwd_settings{$_}{check}} ($_, 'CMD=DS;') || '<undef>')) } @daemons;
	return @output;
};

# EOF postfwd2

__END__

=head1 NAME

postfwd2 - postfix firewall daemon

=head1 SYNOPSIS

B<postfwd2> [OPTIONS] [SOURCE1, SOURCE2, ...]

	Ruleset: (at least one, multiple use is allowed):
	-f, --file <file>		reads rules from <file>
	-r, --rule <rule>		adds <rule> to config
	-s, --scores <v>=<r>		returns <r> when score exceeds <v>

        Server:
        -i, --interface <dev>		listen on interface <dev>
        -p, --port <port>		listen on port <port>
	    --proto <proto>		socket type (tcp or unix)
	    --server_socket <sock>	e.g. tcp:127.0.0.1:10045
        -u, --user <name>		set uid to user <name>
        -g, --group <name>		set gid to group <name>
	    --umask <mask>		umask for master filepermissions
	    --server_umask <mask>	umask for server filepermissions
            --pidfile <path>		create pidfile under <path>
            --min_servers <i>		spawn at least <i> children
	    --max_servers <i>		do not spawn more than <i> children
            --min_spare_servers <i>	minimum idle children
            --max_spare_servers <i>     maximum idle children

        Cache:
        -c, --cache <int>		sets the request-cache timeout to <int> seconds
            --cleanup-requests <int>	cleanup interval in seconds for request cache
            --cache_interface <dev>	listen on interface <dev>
            --cache_port <port>		listen on port <port>
	    --cache_proto <proto>	socket type (tcp or unix)
	    --cache_socket <sock>	e.g. tcp:127.0.0.1:10043
	    --cache_umask <mask>	umask for cache filepermissions
	    --cacheid <list>		list of request items for cache-id
	    --cache-rdomain-only	skip recipient localpart for cache-id
	    --cache-no-sender		skip sender address for cache-id
	    --cache-no-size		skip size for cache-id
	    --no_parent_request_cache	disable parent request cache
	    --no_parent_rate_cache	disable parent rate cache
	    --no_parent_dns_cache	disable parent dns cache (default)
	    --no_parent_cache		disable all parent caches

	Rates:
            --cleanup-rates <int>	cleanup interval in seconds for rate cache

	Control:
	-k, --kill, --stop		terminate postfwd2
	    --reload, --hup		reload postfwd2
	    --watchdog <w>		watchdog timer in seconds
	    --respawn <r>		respawn delay in seconds
	    --failures <f>		max respawn failure counter
	    --daemons <list>		list of daemons to start
            --dumpcache			show cache contents
            --dumpstats			show statistics

	DNS:
	-n, --nodns			skip any dns based test
            --dns_timeout <i>		dns query timeout in seconds
            --dns_timeout_max <i>	disable dnsbl after <i> timeouts
            --dns_timeout_interval <i>	reenable dnsbl after <i> seconds
	    --cache-rbl-timeout <i>	default dns ttl if not specified in ruleset
	    --cache-rbl-default <s>	default dns pattern if not specified in ruleset
	    --cleanup-rbls <i>		cleanup old dns cache items every <i> seconds
	    --dns_async_txt		perform dnsbl A and TXT lookups simultaneously
	    --dns_max_ns_lookups	max names to look up with sender_ns_addrs
	    --dns_max_mx_lookups	max names to look up with sender_mx_addrs

        Optional:
	-t, --test			testing, always returns "dunno"
	-S, --summary <i>		show stats every <i> seconds
            --noidlestats		disables statistics when idle
            --norulestats		disables per rule statistics
	-I, --instantcfg		reloads ruleset on every new request
            --keep_rates		do not clear rate limit counters on reload
	    --config_timeout <i>	parser timeout in seconds

	Plugins:
	    --plugins <file>            loads postfwd plugins from file

	Logging:
        -l, --logname <label>		label for syslog messages
	    --facility <s>		use syslog facility <s>
	    --socktype <s>		use syslog socktype <s>
	    --nodnslog			do not log dns results
	    --anydnslog			log any dns (even cached) results
	    --norulelog			do not log rule actions
	    --nolog|--perfmon		no logging at all
        -v, --verbose			verbose logging, use twice to increase
	    --debug <s>			list of debugging classes

        Information (use only at command-line!):
 	-h, --help			display this help and exit
        -m, --manual			shows program manual
	-V, --version			output version information and exit
	-D, --defaults			show postfwd2 settings and exit
        -C, --showconfig		show postfwd2 ruleset and exit (-v allowed)
        -L, --stdout			redirect syslog messages to stdout
        -q, --quiet			no syslogging, no stdout (-P works for compatibility)

	Obsolete (only for compatibility with postfwd v1):
        -d|--daemon, --shortlog, --dns_queuesize, --dns_retries


=head1 DESCRIPTION


=head2 INTRODUCTION

postfwd2 is written to combine complex postfix restrictions in a ruleset similar to those of the most firewalls.
The program uses the postfix policy delegation protocol to control access to the mail system before a message
has been accepted (please visit L<http://www.postfix.org/SMTPD_POLICY_README.html> for more information). 

postfwd2 allows you to choose an action (e.g. reject, dunno) for a combination of several smtp parameters
(like sender and recipient address, size or the client's TLS fingerprint). Also it offers simple macros/acls
which should allow straightforward and easy-to-read configurations.

I<Features:>

* Complex combinations of smtp parameters

* Combined RBL/RHSBL lookups with arbitrary actions depending on results

* Scoring system

* Date/time based rules

* Macros/ACLs, Groups, Negation

* Compare request attributes (e.g. client_name and helo_name)

* Internal caching for requests and dns lookups

* Built in statistics for rule efficiency analysis


=head2 CONFIGURATION

A configuration line consists of optional item=value pairs, separated by semicolons
(`;`) and the appropriate desired action:

	[ <item1>=<value>; <item2>=<value>; ... ] action=<result>

I<Example:>

	client_address=192.168.1.1 ; sender==no@bad.local ; action=REJECT

This will deny all mail from 192.168.1.1 with envelope sender no@bad.local. The order of the elements
is not important. So the following would lead to the same result as the previous example:

	action=REJECT ; client_address=192.168.1.1 ; sender==no@bad.local

The way how request items are compared to the ruleset can be influenced in the following way:

	====================================================================
	 ITEM == VALUE                true if ITEM equals VALUE
	 ITEM => VALUE                true if ITEM >= VALUE
	 ITEM =< VALUE                true if ITEM <= VALUE
	 ITEM =~ VALUE                true if ITEM ~= /^VALUE$/i
	 ITEM != VALUE                false if ITEM equals VALUE
	 ITEM !> VALUE                false if ITEM >= VALUE
	 ITEM !< VALUE                false if ITEM <= VALUE
	 ITEM !~ VALUE                false if ITEM ~= /^VALUE$/i
	 ITEM =  VALUE                default behaviour (see ITEMS section)
	====================================================================

To identify single rules in your log files, you may add an unique identifier for each of it:

	id=R_001 ; action=REJECT ; client_address=192.168.1.1 ; sender==no@bad.local

You may use these identifiers as target for the `jump()` command (see ACTIONS section below). Leading
or trailing whitespace characters will be ignored. Use '#' to comment your configuration. Others will
appreciate.

A ruleset consists of one or multiple rules, which can be loaded from files or passed as command line
arguments. Please see the COMMAND LINE section below for more information on this topic.

Since postfwd version 1.30 rules spanning span multiple lines can be defined by prefixing the following
lines with one or multiple whitespace characters (or '}' for macros):

	id=RULE001
		client_address=192.168.1.0/24
		sender==no@bad.local
		action=REJECT no access

postfwd versions prior to 1.30 require trailing ';' and '\'-characters:

	id=RULE001; \
		client_address=192.168.1.0/24; \
		sender==no@bad.local; \
		action=REJECT no access


=head2 ITEMS

	id			- a unique rule id, which can be used for log analysis
				  ids also serve as targets for the "jump" command.

	date, time		- a time or date range within the specified rule shall hit
				  # FORMAT:
				  # Feb, 29th
				  date=29.02.2008
				  # Dec, 24th - 26th
				  date=24.12.2008-26.12.2008
				  # from today until Nov, 23rd
				  date=-23.09.2008
				  # from April, 1st until today
				  date=01.04.2008-

	days, months		- a range of weekdays (Sun-Sat) or months (Jan-Dec)
				  within the specified rule shall hit

	score			- when the specified score is hit (see ACTIONS section)
				  the specified action will be returned to postfix
				  scores are set global until redefined!

	request_score		- this value allows to access a request's score. it
				  may be used as variable ($$request_score).

	rbl, rhsbl,	 	- query the specified RBLs/RHSBLs, possible values are:
	rhsbl_client,		  <name>[/<reply>/<maxcache>, <name>/<reply>/<maxcache>]
	rhsbl_sender,		  (defaults: reply=^127\.0\.0\.\d+$ maxcache=3600)
	rhsbl_reverse_client	  the results of all rhsbl_* queries will be combined
				  in rhsbl_count (see below).

	rblcount, rhsblcount	- minimum RBL/RHSBL hitcounts to match. if not specified
				  a single RBL/RHSBL hit will match the rbl/rhsbl items.
				  you may specify 'all' to evaluate all items, and use
				  it as variable in an action (see ACTIONS section)
				  (default: 1)

	sender_localpart,	- the local-/domainpart of the sender address
	sender_domain

	recipient_localpart,	- the local-/domainpart of the recipient address
	recipient_domain

        helo_address            - postfwd2 tries to look up the helo_name. use
                                  helo_address=!!(0.0.0.0/0) to check for unknown.
				  Please do not use this for positive access control
				  (whitelisting), as it might be forged.

        sender_ns_names,        - postfwd2 tries to look up the names/ip addresses
        sender_ns_addrs           of the nameservers for the sender domain part.
				  Please do not use this for positive access control
				  (whitelisting), as it might be forged.

        sender_mx_names,        - postfwd2 tries to look up the names/ip addresses
        sender_mx_addrs           of the mx records for the sender domain part.
				  Please do not use this for positive access control
				  (whitelisting), as it might be forged.

	version			- postfwd2 version, contains "postfwd2 n.nn"
				  this enables version based checks in your rulesets
				  (e.g. for migration). works with old versions too,
				  because a non-existing item always returns false:
				  # version >= 1.10
				  id=R01; version~=1\.[1-9][0-9]; sender_domain==some.org \
				  	; action=REJECT sorry no access

	ratecount		- only available for rate(), size() and rcpt() actions.
				  contains the actual limit counter:
					id=R01; action=rate(sender/200/600/REJECT limit of 200 exceeded [$$ratecount hits])
					id=R02; action=rate(sender/100/600/WARN limit of 100 exceeded [$$ratecount hits])

Besides these you can specify any attribute of the postfix policy delegation protocol.  
Feel free to combine them the way you need it (have a look at the EXAMPLES section below).

Most values can be specified as regular expressions (PCRE). Please see the table below
for details:

	# ==========================================================
	# ITEM=VALUE				TYPE
	# ==========================================================
	id=something				mask = string
	date=01.04.2007-22.04.2007		mask = date (DD.MM.YYYY-DD.MM.YYYY)
	time=08:30:00-17:00:00			mask = time (HH:MM:SS-HH:MM:SS)
	days=Mon-Wed				mask = weekdays (Mon-Wed) or numeric (1-3)
	months=Feb-Apr				mask = months (Feb-Apr) or numeric (1-3)
	score=5.0				mask = maximum floating point value
	rbl=zen.spamhaus.org			mask = <name>/<reply>/<maxcache>[,...]
	rblcount=2				mask = numeric, will match if rbl hits >= 2
        helo_address=<a.b.c.d/nn>               mask = CIDR[,CIDR,...]
        sender_ns_names=some.domain.tld         mask = PCRE
        sender_mx_names=some.domain.tld         mask = PCRE
        sender_ns_addrs=<a.b.c.d/nn>            mask = CIDR[,CIDR,...]
        sender_mx_addrs=<a.b.c.d/nn>            mask = CIDR[,CIDR,...]
	# ------------------------------
	# Postfix version 2.1 and later:
	# ------------------------------
	client_address=<a.b.c.d/nn>		mask = CIDR[,CIDR,...]
	client_name=another.domain.tld		mask = PCRE
	reverse_client_name=another.domain.tld	mask = PCRE
	helo_name=some.domain.tld		mask = PCRE
	sender=foo@bar.tld			mask = PCRE
	recipient=bar@foo.tld			mask = PCRE
	recipient_count=5			mask = numeric, will match if recipients >= 5
	# ------------------------------
	# Postfix version 2.2 and later:
	# ------------------------------
	sasl_method=plain			mask = PCRE
	sasl_username=you			mask = PCRE
	sasl_sender=				mask = PCRE
	size=12345				mask = numeric, will match if size >= 12345
	ccert_subject=blackhole.nowhere.local	mask = PCRE (only if tls verified)
	ccert_issuer=John+20Doe			mask = PCRE (only if tls verified)
	ccert_fingerprint=AA:BB:CC:DD:EE:...	mask = PCRE (do NOT use "..." here)
	# ------------------------------
	# Postfix version 2.3 and later:
	# ------------------------------
	encryption_protocol=TLSv1/SSLv3		mask = PCRE
	encryption_cipher=DHE-RSA-AES256-SHA	mask = PCRE
	encryption_keysize=256			mask = numeric, will match if keysize >= 256
	...

the current list can be found at L<http://www.postfix.org/SMTPD_POLICY_README.html>. Please read carefully about which
attribute can be used at which level of the smtp transaction (e.g. size will only work reliably at END-OF-MESSAGE level).
Pattern matching is performed case insensitive.

Multiple use of the same item is allowed and will compared as logical OR, which means that this will work as expected:

	id=TRUST001; action=OK; encryption_keysize=64
		ccert_fingerprint=11:22:33:44:55:66:77:88:99
		ccert_fingerprint=22:33:44:55:66:77:88:99:00
		ccert_fingerprint=33:44:55:66:77:88:99:00:11
		sender=@domain\.local$

client_address, rbl and rhsbl items may also be specified as whitespace-or-comma-separated values:

	id=SKIP01; action=dunno
		client_address=192.168.1.0/24, 172.16.254.23
	id=SKIP02; action=dunno
		client_address=	10.10.3.32 10.216.222.0/27

The following items must be unique:

	id, minimum and maximum values, rblcount and rhsblcount

Any item can be negated by preceeding '!!' to it, e.g.:

	id=HOST001 ;  hostname == !!secure.trust.local ;  action=REJECT only secure.trust.local please

or using the right compare operator:

	id=HOST001 ;  hostname != secure.trust.local ;  action=REJECT only secure.trust.local please

To avoid confusion with regexps or simply for better visibility you can use '!!(...)':

	id=USER01 ;  sasl_username =~ !!( /^(bob|alice)$/ )  ;  action=REJECT who is that?

Request attributes can be compared by preceeding '$$' characters, e.g.:

	id=R-003 ;  client_name = !! $$helo_name      ;  action=WARN helo does not match DNS
	# or
	id=R-003 ;  client_name = !!($$(helo_name))   ;  action=WARN helo does not match DNS

This is only valid for PCRE values (see list above). The comparison will be performed as case insensitive exact match.
Use the '-vv' option to debug.

These special items will be reset for any new rule:

	rblcount	- contains the number of RBL answers
	rhsblcount	- contains the number of RHSBL answers
	matches		- contains the number of matched items
	dnsbltext	- contains the dns TXT part of all RBL and RHSBL replies in the form
			  rbltype:rblname:<txt>; rbltype:rblname:<txt>; ...

These special items will be changed for any matching rule:

	request_hits	- contains ids of all matching rules

This means that it might be necessary to save them, if you plan to use these values in later rules:

	# set vals
	id=RBL01 ; rhsblcount=all; rblcount=all
		action=set(HIT_rhls=$$rhsblcount,HIT_rbls=$$rblcount,HIT_txt=$$dnsbltext)
		rbl=list.dsbl.org, bl.spamcop.net, dnsbl.sorbs.net, zen.spamhaus.org
		rhsbl_client=rddn.dnsbl.net.au, rhsbl.ahbl.org, rhsbl.sorbs.net
		rhsbl_sender=rddn.dnsbl.net.au, rhsbl.ahbl.org, rhsbl.sorbs.net

	# compare
	id=RBL02 ; HIT_rhls>=1 ; HIT_rbls>=1 ; action=554 5.7.1 blocked using $$HIT_rhls RHSBLs and $$HIT_rbls RBLs [INFO: $$HIT_txt]
	id=RBL03 ; HIT_rhls>=2               ; action=554 5.7.1 blocked using $$HIT_rhls RHSBLs [INFO: $$HIT_txt]
	id=RBL04 ; HIT_rbls>=2               ; action=554 5.7.1 blocked using $$HIT_rbls RBLs [INFO: $$HIT_txt]


=head2 FILES

Since postfwd1 v1.15 and postfwd2 v0.18 long item lists can be stored in separate files:

	id=R001 ;  ccert_fingerprint==file:/etc/postfwd/wl_ccerts ;  action=DUNNO

postfwd2 will read a list of items (one item per line) from /etc/postfwd/wl_ccerts. comments are allowed:

	# client1
	11:22:33:44:55:66:77:88:99
	# client2
	22:33:44:55:66:77:88:99:00
	# client3
	33:44:55:66:77:88:99:00:11

To use existing tables in key=value format, you can use:

	id=R001 ;  ccert_fingerprint==table:/etc/postfwd/wl_ccerts ;  action=DUNNO

This will ignore the right-hand value. Items can be mixed:

	id=R002 ;  action=REJECT
		client_name==unknown
		client_name==file:/etc/postfwd/blacklisted

and for non pcre (comma separated) items:

	id=R003 ;  action=REJECT
		client_address==10.1.1.1, file:/etc/postfwd/blacklisted

	id=R004 ;  action=REJECT
		rbl=myrbl.home.local, zen.spamhaus.org, file:/etc/postfwd/rbls_changing

You can check your configuration with the --show_config option at the command line:

	# postfwd2 --showconfig --rule='action=DUNNO; client_address=10.1.0.0/16, file:/etc/postfwd/wl_clients, 192.168.2.1'

should give something like:

	Rule   0: id->"R-0"; action->"DUNNO"; client_address->"=;10.1.0.0/16, =;194.123.86.10, =;186.4.6.12, =;192.168.2.1"

If a file can not be read, it will be ignored:

	# postfwd2 --showconfig --rule='action=DUNNO; client_address=10.1.0.0/16, file:/etc/postfwd/wl_clients, 192.168.2.1'
	[LOG warning]: error: file /etc/postfwd/wl_clients not found - file will be ignored ?
	Rule   0: id->"R-0"; action->"DUNNO"; client_address->"=;10.1.0.0/16, =;192.168.2.1"

File items are evaluated at configuration stage. Therefore postfwd2 needs to be reloaded if a file has changed

If you want to specify a file, that will be reloaded for each request, you can use lfile: and ltable:

	id=R001; client_address=lfile:/etc/postfwd/client_whitelist; action=dunno

This will check the modification time of /etc/postfwd/client_whitelist every time the rule is evaluated and reload it as
necessary. Of course this might increase the system load, so please use it with care.

The --showconfig option illustrates the difference:

	## evaluated at configuration stage
	# postfwd2 --nodaemon -L --rule='client_address=table:/etc/postfwd/clients; action=dunno' -C
	Rule   0: id->"R-0"; action->"dunno"; client_address->"=;1.1.1.1, =;1.1.1.2, =;1.1.1.3"

	## evaluated for any rulehit
	# postfwd2 --nodaemon -L --rule='client_address=ltable:/etc/postfwd/clients; action=dunno' -C
	Rule   0: id->"R-0"; action->"dunno"; client_address->"=;ltable:/etc/postfwd/clients"

Files can refer to other files. The following is valid.

	-- FILE /etc/postfwd/rules.cf --
	id=R01; client_address=file:/etc/postfwd/clients_master.cf; action=DUNNO

	-- FILE /etc/postfwd/clients_master.cf --
	192.168.1.0/24
	file:/etc/postfwd/clients_east.cf
	file:/etc/postfwd/clients_west.cf

	-- FILE /etc/postfwd/clients_east.cf --
	192.168.2.0/24

	-- FILE /etc/postfwd/clients_west.cf --
	192.168.3.0/24

Remind that there is currently no loop detection (/a/file calls /a/file) and that this feature is only available
with postfwd1 v1.15 and postfwd2 v0.18 and higher.


=head2 ACTIONS

I<General>

Actions will be executed, when all rule items have matched a request (or at least one of any item list). You can refer to
request attributes by preceeding $$ characters, like:

	id=R-003; client_name = !!$$helo_name; action=WARN helo '$$helo_name' does not match DNS '$$client_name'
	# or
	id=R-003; client_name = !!$$helo_name; action=WARN helo '$$(helo_name)' does not match DNS '$$(client_name)'

I<postfix actions>

Actions will be replied to postfix as result to policy delegation requests. Any action that postfix understands is allowed - see
"man 5 access" or L<http://www.postfix.org/access.5.html> for a description. If no action is specified, the postfix WARN action
which simply logs the event will be used for the corresponding rule.

postfwd2 will return dunno if it has reached the end of the ruleset and no rule has matched. This can be changed by placing a last
rule containing only an action statement:

	...
	action=dunno ; sender=@domain.local	# sender is ok
	action=reject				# default deny

I<postfwd2 actions>

postfwd2 actions control the behaviour of the program. Currently you can specify the following:

	jump (<id>)
	jumps to rule with id <id>, use this to skip certain rules.
	you can jump backwards - but remember that there is no loop
	detection at the moment! jumps to non-existing ids will be skipped.

	score (<score>)
	the request's score will be modified by the specified <score>,
	which must be a floating point value. the modificator can be either
		+n.nn	adds n.nn to current score
		-n.nn	sustracts n.nn from the current score
		*n.nn	multiplies the current score by n.nn
		/n.nn	divides the current score through n.nn
		=n.nn	sets the current score to n.nn
	if the score exceeds the maximum set by `--scores` option (see
	COMMAND LINE) or the score item (see ITEMS section), the action
	defined for this case will be returned (default: 5.0=>"REJECT postfwd2 score exceeded").

	set (<item>=<value>,<item>=<value>,...)
	this command allows you to insert or override request attributes, which then may be
	compared to your further ruleset. use this to speed up repeated comparisons to large item lists.
	please see the EXAMPLES section for more information. you may separate multiple key=value pairs
	by "," characters.

	rate (<item>/<max>/<time>/<action>)
	this command creates a counter for the given <item>, which will be increased any time a request
	containing it arrives. if it exceeds <max> within <time> seconds it will return <action> to postfix.
	rate counters are very fast as they are executed before the ruleset is parsed.
	please note that <action> is currently limited to postfix actions (no postfwd actions)!
	    # no more than 3 requests per 5 minutes
	    # from the same "unknown" client
	    id=RATE01 ;  client_name==unknown
	       action=rate(client_address/3/300/450 4.7.1 sorry, max 3 requests per 5 minutes)

	size (<item>/<max>/<time>/<action>)
	this command works similar to the rate() command with the difference, that the rate counter is
	increased by the request's size attribute. to do this reliably you should call postfwd2 from
	smtpd_end_of_data_restrictions. if you want to be sure, you could check it within the ruleset:
	   # size limit 1.5mb per hour per client
	   id=SIZE01 ;  protocol_state==END-OF-MESSAGE ;  client_address==!!(10.1.1.1)
	      action=size(client_address/1572864/3600/450 4.7.1 sorry, max 1.5mb per hour)

	rcpt (<item>/<max>/<time>/<action>)
	this command works similar to the rate() command with the difference, that the rate counter is
	increased by the request's recipient_count attribute. to do this reliably you should call postfwd
	from smtpd_data_restrictions or smtpd_end_of_data_restrictions. if you want to be sure, you could
	check it within the ruleset:
	   # recipient count limit 3 per hour per client
	   id=RCPT01 ;  protocol_state==END-OF-MESSAGE ;  client_address==!!(10.1.1.1)
	      action=rcpt(client_address/3/3600/450 4.7.1 sorry, max 3 recipients per hour)

	ask (<addr>:<port>[:<ignore>])
	allows to delegate the policy decision to another policy service (e.g. postgrey). the first
	and the second argument (address and port) are mandatory. a third optional argument may be
	specified to tell postfwd2 to ignore certain answers and go on parsing the ruleset:
	   # example1: query postgrey and return it's answer to postfix
	   id=GREY; client_address==10.1.1.1; action=ask(127.0.0.1:10031)
	   # example2: query postgrey but ignore it's answer, if it matches 'DUNNO'
	   # and continue parsing postfwd's ruleset
	   id=GREY; client_address==10.1.1.1; action=ask(127.0.0.1:10031:^dunno$)

	wait (<delay>)
	pauses the program execution for <delay> seconds. use this for
	delaying or throtteling connections.

	note (<string>)
	just logs the given string and continues parsing the ruleset.
	if the string is empty, nothing will be logged (noop).

	quit (<code>)
	terminates the program with the given exit-code. postfix doesn`t
	like that too much, so use it with care.

You can reference to request attributes, like

	id=R-HELO ;  helo_name=^[^\.]+$ ;  action=REJECT invalid helo '$$helo_name'


=head2 MACROS/ACLS

Multiple use of long items or combinations of them may be abbreviated by macros. Those must be prefixed by '&&' (two '&' characters).
First the macros have to be defined as follows:

	&&RBLS { rbl=zen.spamhaus.org,list.dsbl.org,bl.spamcop.net,dnsbl.sorbs.net,ix.dnsbl.manitu.net; };

Then these may be used in your rules, like:

	&&RBLS ;  client_name=^unknown$				; action=REJECT
	&&RBLS ;  client_name=(\d+[\.-_]){4}			; action=REJECT
	&&RBLS ;  client_name=[\.-_](adsl|dynamic|ppp|)[\.-_]	; action=REJECT

Macros can contain actions, too:

	# definition
	&&GONOW { action=REJECT your request caused our spam detection policy to reject this message. More info at http://www.domain.local; };
	# rules
	&&GONOW ;  &&RBLS ;  client_name=^unknown$
	&&GONOW ;  &&RBLS ;  client_name=(\d+[\.-_]){4}
	&&GONOW ;  &&RBLS ;  client_name=[\.-_](adsl|dynamic|ppp|)[\.-_]

Macros can contain macros, too:

	# definition
	&&RBLS{
		rbl=zen.spamhaus.org
		rbl=list.dsbl.org
		rbl=bl.spamcop.net
		rbl=dnsbl.sorbs.net
		rbl=ix.dnsbl.manitu.net
	};
	&&DYNAMIC{
		client_name=^unknown$
		client_name=(\d+[\.-_]){4}
		client_name=[\.-_](adsl|dynamic|ppp|)[\.-_]
	};
	&&GOAWAY { &&RBLS; &&DYNAMIC; };
	# rules
	&&GOAWAY ; action=REJECT dynamic client and listed on RBL

Basically macros are simple text substitutions - see the L</PARSER> section for more information.


=head2 PLUGINS

B<Description>

The plugin interface allow you to define your own checks and enhance postfwd's
functionality. Feel free to share useful things!

B<Warning>

Note that the plugin interface is still at devel stage. Please test your plugins
carefully, because errors may cause postfwd to break! It is also
allowed to override attributes or built-in functions, but be sure that you know
what you do because some of them are used internally.

Please keep security in mind, when you access sensible ressources and never, ever
run postfwd as privileged user! Also never trust your input (especially hostnames,
and e-mail addresses).

B<ITEMS>

Item plugins are perl subroutines which integrate additional attributes to requests
before they are evaluated against postfwd's ruleset like any other item of the
policy delegation protocol. This allows you to create your own checks.

plugin-items can not be used selective. these functions will be executed for every
request postfwd receives, so keep performance in mind.

	SYNOPSIS: %result = postfwd_items_plugin{<name>}(%request)

means that your subroutine, called <name>, has access to a hash called %request,
which contains all request attributes, like $request{client_name} and must
return a value in the following form:

	save: $result{<item>} = <value>

this creates the new item <item> containing <value>, which will be integrated in
the policy delegation request and therefore may be used in postfwd's ruleset.

	# do NOT remove the next line
	%postfwd_items_plugin = (

		# EXAMPLES - integrated in postfwd. no need to activate them here.
		
			# allows to check postfwd version in ruleset
	        	"version" => sub {
       	 		       	my(%request) = @_;
				my(%result) = (
       	 	        		"version" => $NAME." ".$VERSION,
				);
       	 		       	return %result;
			},
		
			# sender_domain and recipient_domain
       	 		"address_parts" => sub {
       	 		       	my(%request) = @_;
				my(%result) = ();
       	 			$request{sender} =~ /@([^@]*)$/;
       	 			$result{sender_domain} = ($1 || '');
       	 			$request{recipient} =~ /@([^@]*)$/;
				$result{recipient_domain} = ($1 || '');
       			       	return %result;
			},

	# do NOT remove the next line
	);

B<COMPARE>

Compare plugins allow you to define how your new items should be compared to the ruleset.
These are optional. If you don't specify one, the default (== for exact match, =~ for PCRE, ...)
will be used.

	SYNOPSIS:  <item> => sub { return &{$postfwd_compare{<type>}}(@_); },

	# do NOT remove the next line
	%postfwd_compare_plugin = (

		EXAMPLES - integrated in postfwd. no need to activate them here.
	
			# Simple example
			# SYNOPSIS:  <result> = <item> (return &{$postfwd_compare{<type>}}(@_))
			"client_address"  => sub { return &{$postfwd_compare{cidr}}(@_); },
			"size"            => sub { return &{$postfwd_compare{numeric}}(@_); },
			"recipient_count" => sub { return &{$postfwd_compare{numeric}}(@_); },
	
			# Complex example
			# SYNOPSIS:  <result> = <item>(<operator>, <ruleset value>, <request value>, <request>)
			"numeric" => sub {
				my($cmp,$val,$myitem,%request) = @_;
				my($myresult) = undef;	$myitem ||= "0"; $val ||= "0";
				if ($cmp eq '==') {
					$myresult = ($myitem == $val);
				} elsif ($cmp eq '=<') {
					$myresult = ($myitem <= $val);
				} elsif ($cmp eq '=>') {
					$myresult = ($myitem >= $val);
				} elsif ($cmp eq '!=') {
					$myresult = not($myitem == $val);
				} elsif ($cmp eq '!<') {
					$myresult = not($myitem <= $val);
				} elsif ($cmp eq '!>') {
					$myresult = not($myitem >= $val);
				} else {
					$myresult = ($myitem >= $val);
				};
				return $myresult;
			},

	# do NOT remove the next line
	);

B<ACTIONS>

Action plugins allow to define new postfwd actions. By setting the $stop-flag you can decide to
continue or to stop parsing the ruleset.

	SYNOPSIS:  (<stop rule parsing>, <next rule index>, <return action>, <logprefix>, <request>) =
			<action> (<current rule index>, <current time>, <command name>, <argument>, <logprefix>, <request>)

	# do NOT remove the next line
	%postfwd_actions_plugin = (

		# EXAMPLES - integrated in postfwd. no need to activate them here.
	
			# note(<logstring>) command
			"note"  => sub {
				my($index,$now,$mycmd,$myarg,$myline,%request) = @_;
				my($myaction) = $default_action; my($stop) = 0;
				mylogs 'info', "[RULES] ".$myline." - note: ".$myarg if $myarg;
				return ($stop,$index,$myaction,$myline,%request);
			},
	
			# skips next <myarg> rules
        		"skip" => sub {
				my($index,$now,$mycmd,$myarg,$myline,%request) = @_;
				my($myaction) = $default_action; my($stop) = 0;
				$index += $myarg if ( $myarg and not(($index + $myarg) > $#Rules) );
				return ($stop,$index,$myaction,$myline,%request);
        		},
	
			# dumps current request contents to syslog
        		"dumprequest" => sub {
				my($index,$now,$mycmd,$myarg,$myline,%request) = @_;
				my($myaction) = $default_action; my($stop) = 0;
				map { mylogs 'info', "[DUMP] rule=$index, Attribute: $_=$request{$_}" } (keys %request);
				return ($stop,$index,$myaction,$myline,%request);
        		},

	# do NOT remove the next line
	);


=head2 COMMAND LINE

I<Ruleset>

The following arguments are used to specify the source of the postfwd2 ruleset. This means
that at least one of the following is required for postfwd2 to work.

	-f, --file <file>
	Reads rules from <file>. Please see the CONFIGURATION section
	below for more information.

	-r, --rule <rule>
	Adds <rule> to ruleset. Remember that you might have to quote
	strings that contain whitespaces or shell characters.

I<Scoring>

	-s, --scores <val>=<action>
	Returns <action> to postfix, when the request's score exceeds <val>

Multiple usage is allowed. Just chain your arguments, like:

	postfwd2 -r "<item>=<value>;action=<result>" -f <file> -f <file> ...
	  or
	postfwd2 --scores 4.5="WARN high score" --scores 5.0="REJECT postfwd2 score too high" ...

In case of multiple scores, the highest match will count. The order of the arguments will be
reflected in the postfwd2 ruleset.

I<Networking>

postfwd2 can be run as daemon so that it listens on the network for incoming requests.
The following arguments will control it's behaviour in this case.

	-d, --daemon
	postfwd2 will run as daemon and listen on the network for incoming
	queries (default 127.0.0.1:10045).

	-i, --interface <dev>
	Bind postfwd2 to the specified interface (default 127.0.0.1).

	-p, --port <port>
	postfwd2 listens on the specified port (default tcp/10045).

        --proto <type>
        The protocol type for postfwd's socket. Currently you may use 'tcp' or 'unix' here.
        To use postfwd2 with a unix domain socket, run it as follows:
            postfwd2 --proto=unix --port=/somewhere/postfwd.socket

	-u, --user <name>
	Changes real and effective user to <name>.

	-g, --group <name>
	Changes real and effective group to <name>.

	--umask <mask>
        Changes the umask for filepermissions of the master process (pidfile).
        Attention: This is umask, not chmod - you have to specify the bits that
        should NOT apply. E.g.: umask 077 equals to chmod 700.

	--cache_umask <mask>
        Changes the umask for filepermissions of the cache process (unix domain socket).

	--server_umask <mask>
        Changes the umask for filepermissions of the server process (unix domain socket).

	-R, --chroot <path>
	Chroot the process to the specified path.
	Test this before using - you might need some libs there.

	--pidfile <path>
	The process id will be saved in the specified file.

        --facility <f>
        sets the syslog facility, default is 'mail'

        --socktype <s>
        sets the Sys::Syslog socktype to 'native', 'inet' or 'unix'.
        Default is to auto-detect this depening on module version and os.

	-l, --logname <label>
	Labels the syslog messages. Useful when running multiple
	instances of postfwd.

	--loglen <int>
	Truncates any syslog message after <int> characters.

I<Plugins>

	--plugins <file>
	Loads postfwd plugins from file. Please see http://postfwd.org/postfwd.plugins
	or the plugins.postfwd.sample that is available from the tarball for more info.

I<Optional arguments>

These parameters influence the way postfwd2 is working. Any of them can be combined.

	-v, --verbose
	Verbose logging displays a lot of useful information but can cause
	your logfiles to grow noticeably. So use it with caution. Set the option
	twice (-vv) to get more information (logs all request attributes).

	-c, --cache <int>    (default=600)
	Timeout for request cache, results for identical requests will be
	cached until config is reloaded or this time (in seconds) expired.
	A setting of 0 disables this feature.

	--cache-no-size
	Ignores size attribute for cache comparisons which will lead to better
	cache-hit rates. You should set this option, if you don't use the size
	item in your ruleset.

	--cache-no-sender
	Ignores sender address for cache comparisons which will lead to better
	cache-hit rates. You should set this option, if you don't use the sender
	item in your ruleset.

	--cache-rdomain-only 
	This will strip the localpart of the recipient's address before filling the
	cache. This may considerably increase cache-hit rates.

	--cache-rbl-timeout <timeout>     (default=3600)
	This default value will be used as timeout in seconds for rbl cache items,
	if not specified in the ruleset.

	--cache-rbl-default <pattern>    (default=^127\.0\.0\.\d+$)
	Matches <pattern> to rbl/rhsbl answers (regexp) if not specified in the ruleset.

	--cacheid <item>, <item>, ...
	This csv-separated list of request attributes will be used to construct
	the request cache identifier. Use this only, if you know exactly what you
	are doing. If you, for example, use postfwd2 only for RBL/RHSBL control,
	you may set this to
		postfwd2 --cache=3600 --cacheid=client_name,client_address
	This increases efficiency of caching and improves postfwd's performance.
	Warning: You should list all items here, which are used in your ruleset!

	--cleanup-requests <interval>    (default=600)
	The request cache will be searched for timed out items after this <interval> in
	seconds. It is a minimum value. The cleanup process will only take place, when
	a new request arrives.

	--cleanup-rbls <interval>    (default=600)
	The rbl cache will be searched for timed out items after this <interval> in
	seconds. It is a minimum value. The cleanup process will only take place, when
	a new request arrives.

	--cleanup-rates <interval>    (default=600)
	The rate cache will be searched for timed out items after this <interval> in
	seconds. It is a minimum value. The cleanup process will only take place, when
	a new request arrives.

	-S, --summary <int>    (default=600)
	Shows some usage statistics (program uptime, request counter, matching rules)
	every <int> seconds. This option is included by the -v switch.
	This feature uses the alarm signal, so you can force postfwd2 to dump the stats
	using `kill -ALRM <pid>` (where <pid> is the process id of postfwd).

	Example:
	Aug 19 12:39:45 mail1 postfwd[666]: [STATS] Counters: 213000 seconds uptime, 39 rules
	Aug 19 12:39:45 mail1 postfwd[666]: [STATS] Requests: 71643 overall, 49 last interval, 62.88% cache hits
	Aug 19 12:39:45 mail1 postfwd[666]: [STATS] Averages: 20.18 overall, 4.90 last interval, 557.30 top
	Aug 19 12:39:45 mail1 postfwd[666]: [STATS] Contents: 44 cached requests, 239 cached dnsbl results
	Aug 19 12:39:45 mail1 postfwd[666]: [STATS] Rule ID: R-001   matched: 2704 times
	Aug 19 12:39:45 mail1 postfwd[666]: [STATS] Rule ID: R-002   matched: 9351 times
	Aug 19 12:39:45 mail1 postfwd[666]: [STATS] Rule ID: R-003   matched: 3116 times
	...

	--no-rulestats
	Disables per rule statistics. Keeps your log clean, if you do not use them.
	This option has no effect without --summary or --verbose set.

	-L, --stdout
	Redirects all syslog messages to stdout for debugging. Never use this with postfix!

	-t, --test
	In test mode postfwd2 always returns "dunno", but logs according
	to it`s ruleset. -v will be set automatically with this option.

	-n, --nodns
	Disables all DNS based checks like RBL checks. Rules containing
	such elements will be ignored.

	-n, --nodnslog
	Disables logging of dns events.

	--dns_timeout     (default: 14)
	Sets the timeout for asynchonous dns queries in seconds. This value will apply to
	all dns items in a rule.

	--dns_timeout_max    (default: 10)
	Sets the maximum timeout counter for dnsbl lookups. If the timeouts exceed this value
	the corresponding dnsbl will be deactivated for a while (see --dns_timeout_interval).

	--dns_timeout_interval    (default=1200)
	The dnsbl timeout counter will be cleaned after this interval in seconds. Use this
	in conjunction with the --dns_timeout_max parameter.

	--dns_async_txt
	Perform dnsbl A and TXT lookups simultaneously (otherwise only for listings with at
	least one A record). This needs more network bandwidth due to increased queries but
	might increase throughput because the lookups can be parallelized.

	--dns_max_ns_lookups     (default=0)
	maximum ns names to lookup up with sender_ns_addrs item. use 0 for no maximum.

	--dns_max_mx_lookups     (default=0)
	maximum mx names to lookup up with sender_mx_addrs item. use 0 for no maximum.

	-I, --instantcfg
	The config files, specified by -f will be re-read for every request
	postfwd2 receives. This enables on-the-fly configuration changes
	without restarting. Though files will be read only if necessary
	(which means their access times changed since last read) this might
	significantly increase system load.

	--keep_rates    (default=0)
	With this option set postfwd2 does not clear the rate limit counters on reload. Please
	note that you have to restart (not reload) postfwd with this option if you change
	any rate limit rules.

	--config_timeout    (default=3)
	timeout in seconds to parse a single configuration line. if exceeded, the rule will
	be skipped. this is used to prevent problems due to large files or loops.
	
I<Informational arguments>

These arguments are for command line usage only. Never ever use them with postfix!

	-C, --showconfig
	Displays the current ruleset. Use -v for verbose output.

	-V, --version
	Displays the program version.

	-h, --help
	Shows program usage.

	-m, --manual
	Displays the program manual.

	-D, --defaults
	displays complete postfwd2 settings.

	-P, --perfmon
	This option turns of any syslogging and output. It is included
	for performance testing.


=head2 REFRESH

In daemon mode postfwd2 reloads it's ruleset after receiving a HUP signal. Please see the description of
the '-I' switch to have your configuration refreshed for every request postfwd2 receives.


=head2 EXAMPLES

	## whitelisting
	# 1. networks 192.168.1.0/24, 192.168.2.4
	# 2. client_names *.gmx.net and *.gmx.de
	# 3. sender *@someshop.tld from 11.22.33.44
	id=WL001; action=dunno ; client_address=192.168.1.0/24, 192.168.2.4
	id=WL002; action=dunno ; client_name=\.gmx\.(net|de)$
	id=WL003; action=dunno ; sender=@someshop\.tld$ ; client_address=11.22.33.44

	## TLS control
	# 1. *@authority.tld only with correct TLS fingerprint
	# 2. *@secret.tld only with keysizes >=64
	id=TL001; action=dunno 				; sender=@authority\.tld$ ; ccert_fingerprint=AA:BB:CC..
	id=TL002; action=REJECT wrong TLS fingerprint	; sender=@authority\.tld$
	id=TL003; action=REJECT tls keylength < 64	; sender=@secret\.tld$ ; encryption_keysize=64

	## Combined RBL checks
	# This will reject mail if
	# 1. listed on ix.dnsbl.manitu.net
	# 2. listed on zen.spamhaus.org (sbl and xbl, dns cache timeout 1200s instead of 3600s)
	# 3. listed on min 2 of bl.spamcop.net, list.dsbl.org, dnsbl.sorbs.net
	# 4. listed on bl.spamcop.net and one of rhsbl.ahbl.org, rhsbl.sorbs.net
	id=RBL01 ; action=REJECT listed on ix.dnsbl.manitu.net	; rbl=ix.dnsbl.manitu.net
	id=RBL02 ; action=REJECT listed on zen.spamhaus.org	; rbl=zen.spamhaus.org/127.0.0.[2-8]/1200
	id=RBL03 ; action=REJECT listed on too many RBLs	; rblcount=2 ; rbl=bl.spamcop.net, list.dsbl.org, dnsbl.sorbs.net
	id=RBL04 ; action=REJECT combined RBL+RHSBL check  	; rbl=bl.spamcop.net ; rhsbl=rhsbl.ahbl.org, rhsbl.sorbs.net

	## Message size (requires message_size_limit to be set to 30000000)
	# 1. 30MB for systems in *.customer1.tld
	# 2. 20MB for SASL user joejob
	# 3. 10MB default
        id=SZ001; protocol_state==END-OF-MESSAGE; action=DUNNO; size<=30000000 ; client_name=\.customer1.tld$
        id=SZ002; protocol_state==END-OF-MESSAGE; action=DUNNO; size<=20000000 ; sasl_username==joejob
        id=SZ002; protocol_state==END-OF-MESSAGE; action=DUNNO; size<=10000000
        id=SZ100; protocol_state==END-OF-MESSAGE; action=REJECT message too large

	## Selective Greylisting
	##
	## Note that postfwd does not include greylisting. This setup requires a running postgrey service
	## at port 10031 and the following postfix restriction class in your main.cf:
	##
	##      smtpd_restriction_classes = check_postgrey, ...
	##      check_postgrey = check_policy_service inet:127.0.0.1:10031
	#
	# 1. if listed on zen.spamhaus.org with results 127.0.0.10 or .11, dns cache timeout 1200s
	# 2. Client has no rDNS
	# 3. Client comes from several dialin domains
	id=GR001; action=check_postgrey ; rbl=dul.dnsbl.sorbs.net, zen.spamhaus.org/127.0.0.1[01]/1200
	id=GR002; action=check_postgrey ; client_name=^unknown$
	id=GR003; action=check_postgrey ; client_name=\.(t-ipconnect|alicedsl|ish)\.de$

	## Date Time
	date=24.12.2007-26.12.2007          ;  action=450 4.7.1 office closed during christmas
	time=04:00:00-05:00:00              ;  action=450 4.7.1 maintenance ongoing, try again later
	time=-07:00:00 ;  sasl_username=jim ;  action=450 4.7.1 to early for you, jim
	time=22:00:00- ;  sasl_username=jim ;  action=450 4.7.1 to late now, jim
	months=-Apr                         ;  action=450 4.7.1 see you in may
	days=!!Mon-Fri                      ;  action=check_postgrey

	## Usage of jump
	# The following allows a message size of 30MB for different
	# users/clients while others will only have 10MB.
	id=R001 ; action=jump(R100) ; sasl_username=^(Alice|Bob|Jane)$
	id=R002 ; action=jump(R100) ; client_address=192.168.1.0/24
	id=R003 ; action=jump(R100) ; ccert_fingerprint=AA:BB:CC:DD:...
	id=R004 ; action=jump(R100) ; ccert_fingerprint=AF:BE:CD:DC:...
	id=R005 ; action=jump(R100) ; ccert_fingerprint=DD:CC:BB:DD:...
	id=R099 ; protocol_state==END-OF-MESSAGE; action=REJECT message too big (max. 10MB); size=10000000
	id=R100 ; protocol_state==END-OF-MESSAGE; action=REJECT message too big (max. 30MB); size=30000000

	## Usage of score
	# The following rejects a mail, if the client
	# - is listed on 1 RBL and 1 RHSBL
	# - is listed in 1 RBL or 1 RHSBL and has no correct rDNS
	# - other clients without correct rDNS will be greylist-checked
	# - some whitelists are used to lower the score
	id=S01 ; score=2.6              ; action=check_postgrey
	id=S02 ; score=5.0              ; action=REJECT postfwd score too high
	id=R00 ; action=score(-1.0)     ; rbl=exemptions.ahbl.org,list.dnswl.org,query.bondedsender.org,spf.trusted-forwarder.org
	id=R01 ; action=score(2.5)      ; rbl=bl.spamcop.net, list.dsbl.org, dnsbl.sorbs.net
	id=R02 ; action=score(2.5)      ; rhsbl=rhsbl.ahbl.org, rhsbl.sorbs.net
	id=N01 ; action=score(-0.2)     ; client_name==$$helo_name
	id=N02 ; action=score(2.7)      ; client_name=^unknown$
	...

	## Usage of rate and size
	# The following temporary rejects requests from "unknown" clients, if they
	# 1. exceeded 30 requests per hour or
	# 2. tried to send more than 1.5mb within 10 minutes
	id=RATE01 ;  client_name==unknown ;  protocol_state==RCPT
		action=rate(client_address/30/3600/450 4.7.1 sorry, max 30 requests per hour)
	id=SIZE01 ;  client_name==unknown ;  protocol_state==END-OF-MESSAGE
		action=size(client_address/1572864/600/450 4.7.1 sorry, max 1.5mb per 10 minutes)

	## Macros
        # definition
        &&RBLS { rbl=zen.spamhaus.org,list.dsbl.org,bl.spamcop.net,dnsbl.sorbs.net,ix.dnsbl.manitu.net; };
        &&GONOW { action=REJECT your request caused our spam detection policy to reject this message. More info at http://www.domain.local; };
        # rules
        &&GONOW ;  &&RBLS ;  client_name=^unknown$
        &&GONOW ;  &&RBLS ;  client_name=(\d+[\.-_]){4}
        &&GONOW ;  &&RBLS ;  client_name=[\.-_](adsl|dynamic|ppp|)[\.-_]

	## Groups
	# definition
        &&RBLS{
		rbl=zen.spamhaus.org
		rbl=list.dsbl.org
		rbl=bl.spamcop.net
		rbl=dnsbl.sorbs.net
		rbl=ix.dnsbl.manitu.net
	};
	&&RHSBLS{
		...
	};
	&&DYNAMIC{
        	client_name==unknown
        	client_name~=(\d+[\.-_]){4}
        	client_name~=[\.-_](adsl|dynamic|ppp|)[\.-_]
		...
	};
	&&BAD_HELO{
		helo_name==my.name.tld
		helo_name~=^([^\.]+)$
		helo_name~=\.(local|lan)$
		...
	};
	&&MAINTENANCE{
		date=15.01.2007
		date=15.04.2007
		date=15.07.2007
		date=15.10.2007
		time=03:00:00 - 04:00:00
	};
	# rules
	id=COMBINED    ;  &&RBLS ;  &&DYNAMIC ;  action=REJECT dynamic client and listed on RBL
	id=MAINTENANCE ;  &&MAINTENANCE       ;  action=DEFER maintenance time - please try again later
	
	# now with the set() command, note that long item
	# lists don't have to be compared twice
	id=RBL01    ;  &&RBLS      ;  action=set(HIT_rbls=1)
	id=HELO01   ;  &&BAD_HELO  ;  action=set(HIT_helo=1)
	id=DYNA01   ;  &&DYNAMIC   ;  action=set(HIT_dyna=1)
	id=REJECT01 ;  HIT_rbls==1 ;  HIT_helo==1  ; action=REJECT please see http://some.org/info?reject=01 for more info
	id=REJECT02 ;  HIT_rbls==1 ;  HIT_dyna==1  ; action=REJECT please see http://some.org/info?reject=02 for more info
	id=REJECT03 ;  HIT_helo==1 ;  HIT_dyna==1  ; action=REJECT please see http://some.org/info?reject=03 for more info

	## combined with enhanced rbl features
	#
	id=RBL01 ; rhsblcount=all ; rblcount=all ; &&RBLS ; &&RHSBLS
	     action=set(HIT_dnsbls=$$rhsblcount,HIT_dnsbls+=$$rblcount,HIT_dnstxt=$$dnsbltext)
	id=RBL02 ; HIT_dnsbls>=2  ; action=554 5.7.1 blocked using $$HIT_dnsbls DNSBLs [INFO: $$HIT_dnstxt]


=head2 PARSER

I<Configuration>

The postfwd2 ruleset can be specified at the commandline (-r option) or be read from files (-f). The order of your arguments will be kept. You should
check the parser with the -C | --showconfig switch at the command line before applying a new config. The following call:

	postfwd2 --showconfig \
		-r "id=TEST; recipient_count=100; action=WARN mail with 100+ recipients" \
		-f /etc/postfwd.cf \
		-r "id=DEFAULT; action=dunno";

will produce the following output:

	Rule   0: id->"TEST" action->"WARN mail with 100+ recipients"; recipient_count->"100"
	...
	... <content of /etc/postfwd.cf> ...
	...
	Rule <n>: id->"DEFAULT" action->"dunno"

Multiple items of the same type will be added to lists (see the L</ITEMS> section for more info):

	postfwd2 --showconfig \
		-r "client_address=192.168.1.0/24; client_address=172.16.26.32; action=dunno"

will result in:

	Rule   0: id->"R-0"; action->"dunno"; client_address->"192.168.1.0/24, 172.16.26.32"

Macros are evaluated at configuration stage, which means that

	postfwd2 --showconfig \
		-r "&&RBLS { rbl=bl.spamcop.net; client_name=^unknown$; };" \
		-r "id=RBL001; &&RBLS; action=REJECT listed on spamcop and bad rdns";

will result in:

	Rule   0: id->"RBL001"; action->"REJECT listed on spamcop and bad rdns"; rbl->"bl.spamcop.net"; client_name->"^unknown$"

I<Request processing>

When a policy delegation request arrives it will be compared against postfwd`s ruleset. To inspect the processing in detail you should increase
verbority using use the "-v" or "-vv" switch. "-L" redirects log messages to stdout.

Keeping the order of the ruleset in general, items will be compared in random order, which basically means that

	id=R001; action=dunno; client_address=192.168.1.1; sender=bob@alice.local

equals to

	id=R001; sender=bob@alice.local; client_address=192.168.1.1; action=dunno

Lists will be evaluated in the specified order. This allows to place faster expressions at first:

	postfwd2 --nodaemon -vv -L -r "id=RBL001; rbl=localrbl.local zen.spamhaus.org; action=REJECT" /some/where/request.sample

produces the following

	[LOGS info]: compare rbl: "remotehost.remote.net[68.10.1.7]"  ->  "localrbl.local"
	[LOGS info]: count1 rbl:  "2"  ->  "0"
	[LOGS info]: query rbl:   localrbl.local 7.1.10.68 (7.1.10.68.localrbl.local)
	[LOGS info]: count2 rbl:  "2"  ->  "0"
	[LOGS info]: match rbl:   FALSE
	[LOGS info]: compare rbl: "remotehost.remote.net[68.10.1.7]"  ->  "zen.spamhaus.org"
	[LOGS info]: count1 rbl:  "2"  ->  "0"
	[LOGS info]: query rbl:   zen.spamhaus.org 7.1.10.68 (7.1.10.68.zen.spamhaus.org)
	[LOGS info]: count2 rbl:  "2"  ->  "0"
	[LOGS info]: match rbl:   FALSE
	[LOGS info]: Action: dunno

The negation operator !!(<value>) has the highest priority and therefore will be evaluated first. Then variable substitutions are performed:

	postfwd2 --nodaemon -vv -L -r "id=TEST; action=REJECT; client_name=!!($$heloname)" /some/where/request.sample

will give

	[LOGS info]: compare client_name:     "unknown"  ->  "!!($$helo_name)"
	[LOGS info]: negate client_name:      "unknown"  ->  "$$helo_name"
	[LOGS info]: substitute client_name:  "unknown"  ->  "english-breakfast.cloud8.net"
	[LOGS info]: match client_name:  TRUE
	[LOGS info]: Action: REJECT


I<Ruleset evaluation>

A rule hits when all items (or at least one element of a list for each item) have matched. As soon as one item (or all elements of a list) fails
to compare against the request attribute the parser will jump to the next rule in the postfwd2 ruleset.

If a rule matches, there are two options:

* Rule returns postfix action (dunno, reject, ...)
The parser stops rule processing and returns the action to postfix. Other rules will not be evaluated.

* Rule returns postfwd2 action (jump(), note(), ...)
The parser evaluates the given action and continues with the next rule (except for the jump() or quit() actions - please see the L</ACTIONS> section
for more information). Nothing will be sent to postfix.

If no rule has matched and the end of the ruleset is reached postfwd2 will return dunno without logging anything unless in verbose mode. You may
place a last catch-all rule to change that behaviour:

	... <your rules> ...
	id=DEFAULT ;  action=dunno

will log any request that passes the ruleset without having hit a prior rule.


=head2 DEBUGGING

To debug special steps of the parser the '--debug' switch takes a list of debug classes. Currently the following classes are defined:

	all cache config debugdns devel dns getcache getdns
	getdnspacket rates request setcache setdns
	parent_cache parent_dns_cache parent_rate_cache parent_request_cache
	child_cache  child_dns_cache  child_rate_cache  child_request_cache


=head2 INTEGRATION

I<Integration via daemon mode>

The common way to use postfwd2 is to start it as daemon, listening at a specified tcp port.
postfwd2 will spawn multiple child processes which communicate with a parent cache. This is
the prefered way to use postfwd2 in high volume environments. Start postfwd2 with the following parameters:

	postfwd2 -d -f /etc/postfwd.cf -i 127.0.0.1 -p 10045 -u nobody -g nobody -S

For efficient caching you should check if you can use the options --cacheid, --cache-rdomain-only,
--cache-no-sender and --cache-no-size.

Now check your syslogs (default facility "mail") for a line like:

	Aug  9 23:00:24 mail postfwd[5158]: postfwd2 n.nn ready for input

and use `netstat -an|grep 10045` to check for something like

	tcp  0  0  127.0.0.1:10045  0.0.0.0:*  LISTEN

If everything works, open your postfix main.cf and insert the following

	127.0.0.1:10045_time_limit      = 3600						<--- integration
	smtpd_recipient_restrictions    = permit_mynetworks				<--- recommended
                                  	  reject_unauth_destination			<--- recommended
				  	  check_policy_service inet:127.0.0.1:10045	<--- integration

Reload your configuration with `postfix reload` and watch your logs. In it works you should see
lines like the following in your mail log:

	Aug  9 23:01:24 mail postfwd[5158]: rule=22, id=ML_POSTFIX, client=english-breakfast.cloud9.net[168.100.1.7], sender=owner-postfix-users@postfix.tld, recipient=someone@domain.local, helo=english-breakfast.cloud9.net, proto=ESMTP, state=RCPT, action=dunno

If you want to check for size or rcpt_count items you must integrate postfwd2 in smtp_data_restrictions or
smtpd_end_of_data_restrictions. Of course you can also specify a restriction class and use it in your access
tables. First create a file /etc/postfix/policy containing:

	domain1.local		postfwdcheck
	domain2.local		postfwdcheck
	...

Then postmap that file (`postmap hash:/etc/postfix/policy`), open your main.cf and enter

	# Restriction Classes
	smtpd_restriction_classes       = postfwdcheck, <some more>...				<--- integration
	postfwdcheck                    = check_policy_service inet:127.0.0.1:10045		<--- integration

	127.0.0.1:10045_time_limit      = 3600							<--- integration
	smtpd_recipient_restrictions    = permit_mynetworks,					<--- recommended
                                  	  reject_unauth_destination,				<--- recommended
				  	  ...							<--- optional
				  	  check_recipient_access hash:/etc/postfix/policy,	<--- integration
				  	  ...							<--- optional

Reload postfix and watch your logs.


=head2 TESTING

First you have to create a ruleset (see Configuration section). Check it with

	postfwd2 -f /etc/postfwd.cf -C

There is an example policy request distributed with postfwd, called 'request.sample'.
Simply change it to meet your requirements and use

	postfwd2 -f /etc/postfwd.cf <request.sample

You should get an answer like

	action=<whateveryouconfigured>

For network tests I use netcat:

	nc 127.0.0.1 10045 <request.sample

to send a request to postfwd. If you receive nothing, make sure that postfwd2 is running and
listening on the specified network settings.


=head2 PERFORMANCE

Some of these proposals might not match your environment. Please check your requirements and test new options carefully!

	- use caching options
	- use the correct match operator ==, <=, >=
	- use ^ and/or $ in regular expressions
	- use item lists (faster than single rules)
	- use set() action on repeated item lists
	- use jumps and rate limits
	- use a pre-lookup rule for rbl/rhsbls with empty note() action


=head2 SEE ALSO

See L<http://www.postfix.org/SMTPD_POLICY_README.html> for a description
of how Postfix policy servers work.


=head1 LICENSE

postfwd2 is free software and released under BSD license, which basically means
that you can do what you want as long as you keep the copyright notice:

Copyright (c) 2009, Jan Peter Kessler
All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

 * Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in
   the documentation and/or other materials provided with the
   distribution.
 * Neither the name of the authors nor the names of his contributors
   may be used to endorse or promote products derived from this
   software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY ME ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES,
INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL BE LIABLE FOR ANY DIRECT,
INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.


=head1 AUTHOR

S<Jan Peter Kessler E<lt>info (AT) postfwd (DOT) orgE<gt>>. Let me know, if you have any suggestions.

=cut

