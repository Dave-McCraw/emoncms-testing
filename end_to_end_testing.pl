#!/usr/bin/perl
use LWP::Simple;                # From CPAN
use JSON qw( decode_json );     # From CPAN
use Data::Dumper;               # Perl core module
use strict;                     # Good practice
use warnings;                   # Good practice

# Debug on/off
use constant DEBUG => 0;

# Define a few constants to help us out
use constant {
        PHPFIWA   => 6,
        PHPFINA   => 5,

        TIMESERIES => 1,
        DAILY      => 2,
        
        LOG_TO_FEED => 1,
        ACCUMULATOR => 14,
        KWH_TO_KWHD => 23,
    };

# Key script parameters.
my ($host, $API_key) = @_;
$host = "http://192.168.1.66/emoncms" if !defined $host;
$API_key = "e84e8d580cf593bc70e00f7e23db615c" if !defined $API_key;
print "Testing $host using API key '$API_key'\n\n";

# Submit input to emoncms
sub send_input {
  my ($node_id, $input_value) = @_;
  print "Submit input value $input_value for node $node_id...\n";

  my $req = "$host/input/post.json?node=$node_id&csv=$input_value&apikey=$API_key";
  print "  REQ: $req\n" if DEBUG;

  my $res = get($req);
  print "  RES: $res\n" if DEBUG;

  if (!is_valid_json($res)){
    print "  WARNING: JSON API has not returned JSON! Got '$res'\n";
    return;
  }

  my $json = strip_crap($res);
  print "  Failed (tell me how to handle the JSON!)\n";
  exit (1);
}

# Create an emoncms feed
sub create_feed {
  my ($name, $datatype, $engine, $interval) = @_;
  print "Create feed '$name'...\n";

  my $req = "$host/feed/create.json?name=$name&datatype=$datatype&engine=$engine&interval=$interval&apikey=$API_key";
  print "  REQ: $req\n" if DEBUG;

  my $res = get ($req);
  print "  RES: $res\n" if DEBUG; 

  if (!is_valid_json($res)){
    print "  WARNING: JSON API has not returned JSON! Got '$res'\n";
  }

  my $json = strip_crap($res);
  my $decoded_json = decode_json($json);

  if ($decoded_json->{'success'}){
    print "  Success\n";
    return $decoded_json->{'feedid'};
  }
  else {
    print "  Failed: $decoded_json->{'message'}\n";
    exit (1);
  }
}

sub add_process{
  my ($input_id, $process_id, $argument) = @_;
  print "Add process $process_id ($argument) to input $input_id\n";

  my $req = "$host/input/process/add.json?inputid=$input_id&processid=$process_id&arg=$argument&apikey=$API_key";
  print "  REQ: $req\n" if DEBUG;
  
  my $res = get ($req);
  print "  RES: $res\n" if DEBUG;

  if (!is_valid_json($res)){
    print "  WARNING: JSON API has not returned JSON! Got '$res'\n";
  }

  my $json = strip_crap($res);
  
  my $decoded_json = decode_json($json);
  if ($decoded_json->{'success'}){
    print "  Success\n";
  } 
  else {
    print "  Failed: $decoded_json->{'message'}\n";
    exit (1);
  } 

}

sub validate_feed_value{
  my ($feed_id, $expected_value) = @_;
  print "Check that feed $feed_id has expected value $expected_value\n";
  
  my $req ="$host/feed/value.json?id=$feed_id&apikey=$API_key";
  print "  REQ: $req\n" if DEBUG;
  
  my $res = get ($req);
  print "  RES: $res\n" if DEBUG;

  if (!is_valid_json($res)){
    print "  WARNING: JSON API has not returned JSON! Got '$res'\n";
  }

  my ($value) = $res =~ /"(.*)"/; #Ouch, not so much json here

  if ($value == $expected_value){
    print "  Success\n";
  }
  else {
    print "  Failed: actual value is $value\n";
  }

}

sub delete_feed {
  my ($feed_id) = @_;
  print "Deleting feed $feed_id\n";

  my $req ="$host/feed/delete.json?id=$feed_id&apikey=$API_key";
  print "  REQ: $req\n" if DEBUG;

  my $res = get ($req);
  print "  RES: $res\n" if DEBUG;

  if (!is_valid_json($res)){
    print "  WARNING: JSON API has not returned JSON! Got '$res'\n";
  }

  my ($value) = $res =~ /"(.*)"/; #Ouch, not so much json here


}

sub is_valid_json {
  my $alleged_json = shift;
  return eval { decode_json($alleged_json); 1 };
}

sub strip_crap {
  my $raw_html = shift;
  if (!defined $raw_html || !length $raw_html){
    print "    Can't get JSON from empty string!\n";
    return $raw_html;
  }   
 
  my ($json) = $raw_html =~ /.*(\{.*\}).*/;

  if (!defined $json || !length $json){
    print "    There was no JSON in the string '$raw_html' - are you using the JSON API?\n";
    return $raw_html;
  }

  print "    (got ".length($json)." json chars from ".length($raw_html)." HTML chars)\n" if DEBUG;
  print "    JSON: $json\n" if DEBUG; 
  
  return $json;
}

my $node_id = 1;
my $input_id = 1;

# The user gets a node to call in
send_input($node_id, 1);

# They add a feed for the input
my $input_feed_id = create_feed("Test_input_feed", TIMESERIES, PHPFIWA, 10);
add_process ($input_id, LOG_TO_FEED, $input_feed_id);

# They add an accumulator, too
my $acc_feed_id = create_feed("Test_accumulator_feed", TIMESERIES, PHPFIWA, 10);
add_process ($input_id, ACCUMULATOR, $acc_feed_id);

# They want to see a chart of the daily accumulation
my $daily_feed_id = create_feed("Test_daily_feed", DAILY, PHPFIWA, 10);
add_process ($input_id, KWH_TO_KWHD, $daily_feed_id);

send_input($node_id, 1);
send_input($node_id, 2);
send_input($node_id, 3);

validate_feed_value ($input_feed_id, 3);
validate_feed_value ($acc_feed_id, 6);
validate_feed_value ($daily_feed_id, 6);

print "\n";

print "Now deleting test feeds...\n";
delete_feed($input_feed_id);
delete_feed($acc_feed_id);
delete_feed($daily_feed_id);

exit 1;

# Now add an accumulator and check that shit out:

# Now add a DAILY PHPFINA feed and start logging a daily count to it
#http://192.168.1.66/emoncms/feed/create.json?name=daily_feed&datatype=2&engine=5&interval=10
#http://192.168.1.66/emoncms/input/process/add.json?inputid=1&processid=23&arg=8
