#!/usr/bin/perl
#
# DESCRIPTION
#
#   This script implements the modify command for the Meeting Maker application.
#
#   The modify command is an input command.  The IDM engine sends a modify
#   command to the subscriber to request that the external application modify
#   an entry.  The modify command must contain an ASSOCIATION element.
#
#
# VARIABLES
#
#   SRC_DN
#     Specifies the distinguished name of the entry to modify in the name
#     space of eDirectory.
#
#   CLASS_NAME
#     Specifies the base class of the entry being modified.  This attribute
#     is required for modify events.
#
#   EVENT_ID
#     Specifies an identifier to identify a particular instance of the command.
#
#   ASSOCIATION
#     Specifies the unique identifier for the entry in the external
#     application.  This element is required for modify events.
#
#   ADD_<ATTR_NAME>
#     Specifies one or more values to add to <ATTR_NAME>, where <ATTR_NAME> is
#     literally replaced by the name of the attribute being modified.
#
#   REMOVE_<ATTR_NAME>
#     Specifies one or more values to remove to <ATTR_NAME>, where <ATTR_NAME>
#     is literally replaced by the name of the attribute being modified.
#
#   REMOVE_ALL_<ATTR_NAME>
#     Instructs to remove all values associated with <ATTR_NAME>, where
#     <ATTR_NAME> is literally replaced by the name of the attribute being
#     modified.
#
#
# REPLY FORMAT
#
#    The receiving application should respond to the modify with a STATUS
#    and an optional STATUS_MESSAGE which can be returned for IDM engine
#    processing and logging facilities.
#
#    The format for returning STATUS and STATUS_MESSAGE are as follows:
#
#      STATUS_<LEVEL> "<optional message>"
#
#        <LEVEL> may be one of the following values:
#        * SUCCESS
#        * WARNING
#        * ERROR
#        * RETRY
#        * FATAL
#
#      Note:  FATAL will shutdown the driver, RETRY will retry the event
#             later on.
#
use strict;
use MIME::Base64;
use OMAPI::CORE;
use OMAPI::DHCP;
use Data::Dumper;
use IDMLib;  # include the IDM Library

our $global_config;
our %config;
our $SCRIPT_DIR;

require $SCRIPT_DIR."/"."config.pl";


my $i = new IDMLib();
my $RC = 1;
my $result = '';

# Log and Trace some messages
$i->logger($global_config->{TRACEPRIO}, "modify.pl", "modify.pl");
$i->trace("*** $SCRIPT_DIR/modify.pl ***");

# connect to dhcp server
my $omapi = new OMAPI::DHCP($config{'servername'}, $config{'port'}, $config{'loginkey'});
if (!defined $omapi) {
   $i->status_retry("Could not connect to DHCP server with OMAPI");
   exit;
}

# retrieve variables
my $class_name = $i->idmgetvar('CLASS_NAME');
my $ASSOCIATION = $i->idmgetvar('ASSOCIATION');

my @fields;
@fields = split("\n",$i->idmgetvar('DirXMLjnsuDeviceName'));
my $hostID = $fields[0];
@fields = split("\n",$i->idmgetvar('DirXMLjnsuHWAddress'));
my $hw_addr = $fields[0];
#print "[$hw_addr]\n";
@fields = split("\n",$i->idmgetvar('DirXMLjnsuDHCPAddress'));
my $ip_addr = $fields[0];
@fields = split("\n",$i->idmgetvar('DirXMLjnsuDDNSPrefix'));
my $ddns_prefix = $fields[0];
@fields = split("\n",$i->idmgetvar('DirXMLjnsuDHCPGroup'));
my $dhcp_group = $fields[0];
@fields = split("\n",$i->idmgetvar('DirXMLjnsuDescription'));
my $description = $fields[0];
@fields = split("\n",$i->idmgetvar('DirXMLjnsuStaticAddr'));
my $static_addr = '';
$static_addr = $fields[0];
my @static_addrs = split("\n",$i->idmgetvar('AllStaticAddrs'));
print "test - modify - $static_addr\n";
print Dumper(@static_addrs);
@fields = split("\n",$i->idmgetvar('DirXMLjnsuDisabled'));
my $disabled = $fields[0];
@fields = split("\n",$i->idmgetvar('DirXMLjnsuMDisabled'));
my $mdisabled = $fields[0];
@fields = split("\n",$i->idmgetvar('DirXMLjnsuRegVersion'));
my $reg_version = 0;
$reg_version = $fields[0];

if ($mdisabled eq "true") {
   $disabled = "true";
}


# Split the association into the prefix "jnsu (fields[0]) and the hardware address
# (fields[1])
@fields = split /-/, $ASSOCIATION;

#make sure hardware address matches the association
if ( $hw_addr ne $fields[1] ) {
   $i->status_error("Invalid Association $ASSOCIATION for hardware address [$hw_addr] [".$fields[1]."]");
   exit 1;
}

if ($class_name ne "DirXMLjnsuNetworkDevice"){
  $i->status_error("Unsupported Object Type");
  exit 7;
}

# prepare statements for the addition of the host entry
my $statements = "";
if ($disabled eq 'true') {
   $statements .= "\ndeny booting 1;";
}
if ( $ddns_prefix ne '') {
   $statements .= "\noption host-name \"$ddns_prefix\";";
}

if ($description =~/^T1Fixed/) {
   #$statements .= "\noption host-name \"$ddns_prefix\";";
   #$statements .= "\nnext-server 130.127.10.110;";
}


if ($statements ne '') {
   $statements .= "\n";
}

# delete existing entry
$omapi->Delete_Host( {'hardware-address' => $hw_addr } );
$hostID =~tr/\:/-/;
my $options = {
    'name'                  =>  $hostID,
    'hardware-address'      =>  $hw_addr
              };


if ($statements ne '') {
   ${$options}{'statements'} = $statements;
}


if ($static_addr eq "true") {

   ${$options}{'ip-address'} = join(".", @static_addrs);

   # add to dhcp group if present
   if ($dhcp_group ne '') {
      ${$options}{'group'} = $dhcp_group;
   }
}



# add modified entry if registered
if ($reg_version >= 1) {
   $result = $omapi->Create_Host ( $options );
} else {
   $result = 1;
}

if ($result ne '') {
  # The modify was successful
  $i->status_success("Modified DirXMLjnsuNetworkDevice $ASSOCIATION");
}
else{
  $i->status_error("Error Modifying DirXMLjnsuNetworkDevice $ASSOCIATION");
}
