unit setup_centos_class;
{$MODE DELPHI}
//{$mode objfpc}{$H+}
{$LONGSTRINGS ON}

interface

uses
  Classes, SysUtils,RegExpr in 'RegExpr.pas',unix,setup_libs,distriDetect;
type
  TStringDynArray = array of string;
  type
  tcentos=class


private
       libs:tlibs;
       ARCH:Integer;
       without_clamav:boolean;
       function CheckCyrus():string;
       function CheckDevcollectd():string;
       function CheckSelinux():string;
       function DisableSeLinux():string;
       function Explode(const Separator, S: string; Limit: Integer = 0):TStringDynArray;
       function RPMFORGE():boolean;
       function ATRPMS():boolean;
       function ELREPO():boolean;
       function IsRPMForgeAsked:boolean;
       function IsRPMForgeSelected:boolean;
       function IsskipBrokenExists():boolean;
       function IsNogpgCheckExists():boolean;



public
      distri:tdistriDetect;
      constructor Create();
      function CheckBaseSystem():string;
      procedure Free;
      function InstallPackageLists(list:string):boolean;
      procedure Show_Welcome;
      function checkSamba():string;
      function checkApps(l:tstringlist):string;
      function CheckPostfix():string;
      function InstallPackageListsSilent(list:string):boolean;
      function checkSQuid():string;
      function CheckBasePHP():string;
      function CheckPDNS():string;
      function CheckZabbix():string;
      function CheckOpenVPN():string;
      procedure DennouRuby();
      function  EPEL():boolean;
END;

implementation

constructor tcentos.Create();
begin
 without_clamav:=false;
libs:=tlibs.Create;
libs.COMMANDLINE_PARAMETERS('--without-clamav');
ARCH:=libs.ArchStruct();

end;
//#########################################################################################
procedure tcentos.Free();
begin
  libs.Free;
end;
//#########################################################################################
procedure tcentos.Show_Welcome;
var
   base,postfix,u,cyrus,samba,squid,selinux,pdns,zabbix,openvpn:string;
begin

   if not FileExists('/usr/bin/yum') then begin
      writeln('Your system does not store /usr/bin/yum utils, this program must be closed...');
      exit;
    end;
    if not FileExists('/tmp/zypper-update') then begin
       fpsystem('touch /tmp/zypper-update');
       fpsystem('/usr/bin/yum check-update');
    end;



    writeln('Checking.............: system...');
    writeln('Checking.............: SeLinux...');

    selinux:=trim(CheckSelinux());
    if selinux='y' then begin
        writeln('Artica is not compliance with SeLinux installed on your system...');
        writeln('Do you want to uninstall it ? [Y]');
        readln(u);
        if length(u)=0 then u:='Y';
        if u='Y' then DisableSeLinux();
    end;

    RPMFORGE();




    writeln('Checking.............: Base system...');
    base:=CheckBaseSystem();
    writeln('Checking.............: Postfix system...');
    postfix:=trim(CheckPostfix());
    writeln('Checking.............: Cyrus system...');
    cyrus:=trim(CheckCyrus());
    writeln('Checking.............: Files Sharing system...');
    samba:=checkSamba();
    writeln('Checking.............: Squid proxy and securities...');
    squid:=checkSQuid();
    writeln('Checking.............: PowerDNS System...');
    pdns:=CheckPDNS();
    writeln('Checking.............: Zabbix System...');
    zabbix:=CheckZabbix();
    writeln('Checking.............: OpenVPN System...');
    openvpn:=CheckOpenVPN();
    u:=libs.INTRODUCTION(base,postfix,cyrus,samba,squid,openvpn);

    writeln('You have selected the option : ' + u);

    if length(u)=0 then begin
        if length(base)>0 then u:='B';
    end;

    if u='B' then begin
        InstallPackageLists(base);
        //DennouRuby();
        Show_Welcome();
        exit;
    end;
    
    if length(u)=0 then begin
       Show_Welcome();
        exit;
    end;

    if lowercase(u)='a' then begin
       InstallPackageLists(base + ' ' + postfix+' '+cyrus+' '+samba+' '+squid);
       fpsystem('/usr/share/artica-postfix/bin/artica-make APP_ROUNDCUBE3');
       fpsystem('/etc/init.d/artica-postfix restart');
       Show_Welcome();
       exit;
    end;


    if u='1' then begin
          InstallPackageLists(postfix);
          Show_Welcome;
          exit;
    end;

   if u='2' then begin
          InstallPackageLists(cyrus);
          fpsystem('/usr/share/artica-postfix/bin/artica-make APP_ROUNDCUBE3');
          fpsystem('/etc/init.d/artica-postfix restart');
          Show_Welcome;
          exit;
    end;

   if u='3' then begin
          InstallPackageLists(samba);
          if FileExists('/etc/init.d/artica-postfix') then  begin
             fpsystem('/etc/init.d/artica-postfix restart samba >/dev/null 2>&1 &');
             fpsystem('/usr/share/artica-postfix/bin/artica-install --nsswitch');
          end;
          Show_Welcome;
          exit;
    end;

   if u='4' then begin
          InstallPackageLists(squid);
          Show_Welcome;
          exit;
    end;

   if u='8' then begin
          InstallPackageLists(zabbix);
          Show_Welcome;
          exit;
    end;

   if u='7' then begin
          InstallPackageLists(pdns);
          Show_Welcome;
          exit;
    end;


   if u='9' then begin
          InstallPackageLists(openvpn);
          Show_Welcome;
          exit;
    end;

    if length(u)=0 then begin
       if length(base)=0 then begin
          InstallPackageLists(postfix+' '+cyrus+' '+samba+' '+squid);
          libs.InstallArtica();
       end;
       Show_Welcome;
       exit;
    end;


end;
//#########################################################################################
function tcentos.InstallPackageLists(list:string):boolean;
var
   cmd:string;
   u  :string;
   i  :integer;
   ll :TStringDynArray;
   fulllist:string;
   nogpgcheck:string;
   skipbroken:string;
begin
if length(trim(list))=0 then exit;
result:=false;

writeln('');
writeln('The following package(s) must be installed in order to perform continue setup');
writeln('');
writeln('-----------------------------------------------------------------------------');
writeln('"',list,'"');
writeln('-----------------------------------------------------------------------------');
writeln('');
writeln('Do you allow install these packages? [Y]');

if not libs.COMMANDLINE_PARAMETERS('--silent') then begin
   readln(u);
end else begin
    u:='y';
end;


if length(u)=0 then u:='y';

if LowerCase(u)<>'y' then exit;
if IsNogpgCheckExists() then nogpgcheck:=' --nogpgcheck';
if IsskipBrokenExists() then skipbroken:=' --skip-broken';

   fpsystem('/usr/bin/yum update -y '+nogpgcheck+''+ skipbroken);
   ll:=Explode(',',list);
   for i:=0 to length(ll)-1 do begin
       if length(trim(ll[i]))>0 then begin
          writeln('');
          writeln('');
          writeln('');
          writeln('');
          writeln('-----------------------------------------------------------------------------');
          writeln('         Installing ', trim(ll[i]),' package number ',i,'/',length(ll));
          writeln('-----------------------------------------------------------------------------');
          fpsystem('/usr/bin/yum install -y '+nogpgcheck+''+ skipbroken+' ' + trim(ll[i]));
       end;
   end;
   if FileExists('/usr/bin/package-cleanup') then begin
      fpsystem('/usr/bin/package-cleanup  -y --cleandupes');
   end;


   if FileExists('/tmp/packages.list') then fpsystem('/bin/rm -f /tmp/packages.list');
   result:=true;


end;
//#########################################################################################
function tcentos.IsskipBrokenExists():boolean;
var
   l:TstringList;
   RegExpr:TRegExpr;
   i:integer;
begin
     result:=false;
     if FileExists('/etc/artica-postfix/yum.skip-broken.exists') then exit(true);
     if FileExists('/etc/artica-postfix/yum.skip-broken.notexists') then exit(false);
     if not FileExists('/tmp/yum.help') then fpsystem('/usr/bin/yum install --help >/tmp/yum.help 2>&1');
     ForceDirectories('/etc/artica-postfix');
     l:=Tstringlist.Create;
     RegExpr:=TRegExpr.Create;
     RegExpr.Expression:='skip-broken';
     l.LoadFromFile('/tmp/yum.help');
     for i:=0 to l.Count-1 do begin
         if RegExpr.Exec(l.Strings[i]) then begin
           fpsystem('/bin/touch /etc/artica-postfix/yum.skip-broken.exists');
           l.free;
           RegExpr.free;
           exit(true);
         end;
     end;
     fpsystem('/bin/touch /etc/artica-postfix/yum.skip-broken.notexists');
     l.free;
     RegExpr.free;

end;
//#########################################################################################
function tcentos.IsNogpgCheckExists():boolean;
var
   l:TstringList;
   RegExpr:TRegExpr;
   i:integer;
begin
     result:=false;
     if FileExists('/etc/artica-postfix/yum.nogpgcheck.exists') then exit(true);
     if FileExists('/etc/artica-postfix/yum.nogpgcheck.notexists') then exit(false);
     if not FileExists('/tmp/yum.help') then fpsystem('/usr/bin/yum install --help >/tmp/yum.help 2>&1');
     ForceDirectories('/etc/artica-postfix');
     l:=Tstringlist.Create;
     RegExpr:=TRegExpr.Create;
     RegExpr.Expression:='nogpgcheck';
     l.LoadFromFile('/tmp/yum.help');
     for i:=0 to l.Count-1 do begin
         if RegExpr.Exec(l.Strings[i]) then begin
           fpsystem('/bin/touch /etc/artica-postfix/yum.nogpgcheck.exists');
           l.free;
           RegExpr.free;
           exit(true);
         end;
     end;
     fpsystem('/bin/touch /etc/artica-postfix/yum.nogpgcheck.notexists');
     l.free;
     RegExpr.free;

end;


function tcentos.IsRPMForgeAsked:boolean;
begin
result:=false;
if FileExists('/tmp/IsRPMForge') then result:=true;
if FileExists('/tmp/IsNotRPMForge') then result:=true;
end;
//#########################################################################################
function tcentos.IsRPMForgeSelected:boolean;
begin
result:=false;
if FileExists('/tmp/IsRPMForge') then result:=true;
end;



function tcentos.InstallPackageListsSilent(list:string):boolean;
var
   cmd:string;
   u  :string;
   i  :integer;
   ll :TStringDynArray;
   fulllist:string;
begin
if length(trim(list))=0 then exit;
result:=false;
   fpsystem('/usr/bin/yum update --nogpgcheck -y');
   ll:=Explode(',',list);
   for i:=0 to length(ll)-1 do begin
       if length(trim(ll[i]))>0 then begin
          fulllist:=fulllist + ' ' +  trim(ll[i]);
          writeln('');
          writeln('Installing ', trim(ll[i]));
          writeln('');
          fpsystem('/usr/bin/yum -y install ' + trim(ll[i]));
          writeln('');

       end;
   end;



   if FileExists('/tmp/packages.list') then fpsystem('/bin/rm -f /tmp/packages.list');
   result:=true;


end;
//#########################################################################################
function tcentos.CheckSelinux():string;
var
   l:TstringList;
   f:string;
   i:integer;
   RegExpr:TRegExpr;
begin
result:='';
if not FileExists('/etc/selinux/config') then exit();
l:=TstringList.Create;
l.LoadFromFile('/etc/selinux/config');
RegExpr:=TRegExpr.Create;
RegExpr.Expression:='SELINUX=(.+)';
for i:=0 to l.Count-1 do begin
     if RegExpr.Exec(l.Strings[i]) then begin
         if trim(RegExpr.Match[1])<>'disabled' then begin
            result:='y';
            break;
         end;
     end;
end;
RegExpr.Free;
l.Free;
end;
//#########################################################################################
function tcentos.DisableSeLinux():string;
var
   l:TstringList;
begin
if not FileExists('/etc/selinux/config') then exit();
l:=TstringList.Create;
l.Add('SELINUX=disabled');
l.Add('SELINUXTYPE=targeted');
l.SaveToFile('/etc/selinux/config');
l.free;
Writeln('You need to reboot your computer after Artica installation.....');

end;
//#########################################################################################

function tcentos.CheckBaseSystem():string;
var
   l:TstringList;
   f:string;
   i:integer;
   c:integer;
   distri:tdistriDetect;
   MinorVersion:Integer;
begin
f:='';
distri:=tdistriDetect.Create();
l:=TstringList.Create;
l.Add('hal');
l.Add('vixie-cron');
l.Add('file');
l.Add('hdparm');
l.Add('less');
l.Add('nscd');
l.Add('rdate');
l.Add('rsync');
l.Add('rsh');
l.Add('openssh');
l.Add('strace');
l.Add('sysfsutils');
l.Add('tcsh');
l.Add('time');
l.Add('eject');
l.Add('pciutils ');
l.Add('usbutils');
l.add('lshw');
l.add('scons');
l.add('quota');

//LDAP
if not FileExists('/etc/artica-postfix/NO_DATABASES_ENGINES') then begin
   l.Add('openldap-servers');
   l.Add('openldap-clients');
end;

//NFS
l.add('nfs-utils');
l.add('nfs-utils-lib');
l.add('nfswatch');
l.add('gfs2-utils');

//wifi
if IsRPMForgeSelected then l.add('hostapd');

//DRDB
//l.Add('drbd83');

//cryptage
l.add('cryptsetup-luks');

l.Add('openssl');

//PHP+LIGHTTPD
l.Add('libmcrypt');
l.Add('lighttpd-fastcgi');
l.Add('php-ldap ');
l.Add('php-mysql');
l.Add('php-imap ');
l.Add('php-pear');
l.Add('php-gd');
l.add('php-xml');
l.Add('php-pear-Log');
l.Add('php-pecl-mailparse');
l.add('php-pear-Mail-Mime');
l.add('php-pear-Net-Sieve');
l.Add('php-mbstring');
l.Add('php-mcrypt');
if IsRPMForgeSelected then  l.add('php-pecl-apc');
if IsRPMForgeSelected then  l.add('php-pecl-json'); //lighttpd
l.add('php-pecl-Fileinfo');
l.Add('lighttpd');

//Apache
l.add('httpd');
l.add('httpd-devel');
l.add('mod_ssl');

l.Add('rrdtool');
l.Add('rrdtool-devel');
l.Add('perl-File-Tail');

//OCS
l.Add('perl-Module-Build');
l.Add('perl-Net-Server');
L.Add('perl-SOAP-Lite');
l.add('perl-Net-IP');
l.add('perl-XML-Simple');

l.add('perl-IO-Compress-Base');
l.add('perl-IO-Compress-Bzip2');
l.add('perl-IO-Compress-Zlib');


//l.add('perl-Compress-Zlib');
//l.add('perl-LWP');
//l.add('perl-Digest-MD5');
l.add('perl-Net-SSLeay');
l.add('OpenIPMI-tools');
l.add('dnsmasq');
l.add('fuse-davfs2');


//l.add('perl-Compress-Zlib');

l.add('perl-DBI');
L.add('perl-DBD-MySQL');
L.add('perl-Apache-DBI');
l.add('perl-Tie-IxHash');
l.add('perl-Socket6');
l.add('perl-IO-Socket-INET6');
L.add('mod_perl');
l.add('iscsi-initiator-utils');

l.Add('mysql-devel');
if not FileExists('/etc/artica-postfix/NO_DATABASES_ENGINES') then l.Add('mysql-server');
l.Add('perl-libwww-perl');

l.Add('cyrus-sasl-ldap');
l.Add('cyrus-sasl');
l.add('perl-Authen-SASL');
l.Add('sudo');
L.add('autofs');
l.add('fuse-sshfs');
L.add('fuse');

//openvpn


//xapian
l.add('catdoc');
l.add('antiword');
l.add('libwpd-tools');
l.add('unrtf');
l.add('xpdf');

//zabix
l.add('upx');

//DEVEL
l.Add('gcc ');
l.Add('make');
l.add('cmake');
l.add('bison');
l.add('glib-devel');
l.add('expat-devel'); //for squid
l.add('libxml2-devel'); //for squid
l.add('pcre-devel'); //for squid
if not FileExists('/etc/artica-postfix/NO_DATABASES_ENGINES') then l.add('openldap-devel'); //for squid
l.add('byacc');
l.add('flex');
l.add('gcc-c++');
if not without_clamav then l.add('clamav-devel');//for c-icap
l.add('gdbm-devel');
l.add('cyrus-sasl-devel');
l.add('db4-devel');
l.add('krb5-devel');
l.add('libgssapi-devel');
l.add('imake');  //makedepend
l.add('unixODBC-devel');
l.add('unixODBC');
l.add('php-devel');
l.add('freetype-devel');
//L.add('t1lib');
//l.add('t1lib-devel');
//l.add('libpaper-devel');
l.add('bzip2-devel');
if IsRPMForgeSelected then l.add('GeoIP');
if IsRPMForgeSelected then l.add('GeoIP-devel');


l.add('kernel-devel');
l.add('aspell-devel');
l.add('curl-devel');
l.add('ncurses-devel');
l.add('e2fsprogs-devel');
l.add('freetype-devel');
l.add('glibc-devel');
l.add('keyutils-libs-devel');
l.add('krb5-devel');
l.add('libgcc');
l.add('libidn-devel');
l.add('libjpeg-devel');
l.add('libpng-devel');
l.add('libselinux-devel');
l.add('libsepol-devel');
l.add('libstdc++-devel');
l.add('libX11-devel');
l.add('libXau-devel');
l.add('libXdmcp-devel');
l.add('libXpm-devel');
l.add('net-snmp-devel');
l.add('openssl-devel');
l.add('tcp_wrappers');
l.add('zlib-devel');
l.add('gd-devel');
l.add('libtool-ltdl-devel');
l.add('libaio-devel');
l.add('libattr-devel');
l.add('libmhash-devel');
l.add('readline-devel');
l.add('libpcap-devel');
l.add('libcap-devel');
l.add('tcp_wrappers');
l.add('rsync');
l.add('stunnel');
l.add('monit');
l.add('boost-filesystem');
l.add('boost-system');
l.add('libicu');
//l.add('openafs-devel');
//l.add('java-1.6.0-openjdk');

//clamav
l.add('libtool-ltdl-devel');
//l.add('libtommath-devel');

//dhcp gateway
l.Add('dhcp');


l.Add('ntp');
l.Add('iproute');
l.add('vconfig');
l.Add('libusb-devel');
l.Add('perl-Inline');
l.Add('libcdio');
l.Add('curl');

//sensors
l.Add('lm_sensors');
l.Add('lm_sensors-devel');
l.add('sysstat');

//compression
l.Add('bzip2');
l.Add('arj');
l.add('zip');
l.add('unzip');

//Backuppc
l.add('perl-Archive-Zip');
l.add('perl-File-RsyncP');
l.add('perl-Time-modules');
l.add('perl-XML-RSS');
l.add('perl-DateTime-Format-Mail');
l.add('perl-DateTime-Format-W3CDTF');
l.add('perl-DateTime');
l.add('perl-Params-Validate');
l.add('perl-Time-modules');
L.add('perl-suidperl');
l.add('perl-Class-Singleton');
l.add('MySQL-python');

//lvm
if not libs.COMMANDLINE_PARAMETERS('--without-lvm') then begin
   l.add('lvm2');
end;


l.Add('htop');
l.Add('telnet');
l.Add('lsof');
l.add('yum-utils');
//l.Add('dar');
//l.Add('preload');
c:=0;
fpsystem('/bin/rm -rf /tmp/packages.list');
writeln('Check base system verify ' + IntTOstr(l.Count-1) +' packages');
for i:=0 to l.Count-1 do begin
     if not libs.RPM_is_application_installed(l.Strings[i]) then begin
          f:=f + ',' + l.Strings[i];
          inc(c);
     end;
end;

writeln('Check base system  ' + IntTOstr(c) +' packages to be installed');

 result:=f;
end;
//#########################################################################################
function tcentos.CheckZabbix():string;
var
   l:TstringList;
   f:string;
   i:integer;

begin
f:='';
l:=TstringList.Create;
l.add('zabbix');
l.add('zabbix-web');
l.add('zabbix-agent');
fpsystem('/bin/rm -rf /tmp/packages.list');

for i:=0 to l.Count-1 do begin
     if not libs.RPM_is_application_installed(l.Strings[i]) then begin
          f:=f + ',' + l.Strings[i];
     end;
end;



 result:=f;

end;
//#########################################################################################
function tcentos.CheckOpenVPN():string;
var
   l:TstringList;
   f:string;
   i:integer;

begin
f:='';
l:=TstringList.Create;
l.add('bridge-utils');
l.add('openvpn');
l.add('ipsec-tools');
fpsystem('/bin/rm -rf /tmp/packages.list');

for i:=0 to l.Count-1 do begin
     if not libs.RPM_is_application_installed(l.Strings[i]) then begin
          f:=f + ',' + l.Strings[i];
     end;
end;
result:=f;
end;
//#########################################################################################






function tcentos.CheckPostfix():string;
var
   l:TstringList;
   f:string;
   i:integer;

begin
f:='';
l:=TstringList.Create;
l.Add('razor-agents');
l.add('sendmail-devel');
l.Add('perl-Crypt-SSLeay');
l.add('perl-Net-SSLeay');
l.Add('perl-Convert-TNEF');
l.Add('perl-HTML-Parser');
l.Add('perl-Archive-Zip');
l.Add('perl-Font-TTF');
l.Add('perl-BerkeleyDB');
l.add('gd');
l.Add('wv');
l.Add('postfix');
//l.add('dkim-milter');
l.add('spamass-milter');
l.add('sendmail-devel');
l.add('milter-greylist');
//l.add('mimedefang');
l.Add('spamassassin');
l.Add('mailman');
l.add('postfix-pflogsumm');

//ASSP

l.add('perl-IO-Compress');//Bzip2.pm
l.add('perl-Email-Valid');// */Email/Valid.pm
l.add('perl-File-ReadBackwards'); // **/File/ReadBackwards.pm
l.add('perl-Mail-SPF');// Mail/SPF.pm
l.add('perl-Email-MIME'); // MIME/Modifier.pm
l.add('perl-Mail-SRS'); // Mail/SRS.pm
l.add('perl-Net-DNS'); // Net/DNS.pm
// Sys/Syslog.pm
l.add('perl-LDAP');// Net/LDAP.pm
l.add('perl-Email-Send');// Email/Send.pm
l.add('perl-IO-Socket-SSL'); // IO/Socket/SSL.pm

//Zarafa
if IsRPMForgeSelected then l.add('libgsasl-devel');

//FuzzyOCR
l.add('netpbm');
l.add('gifsicle');
l.add('giflib');
l.add('giflib-utils');
l.add('gocr');
l.add('ocrad');
l.add('ImageMagick');
l.add('tesseract');
l.add('perl-String-Approx');
l.add('perl-MLDBM');
l.add('aspell');
l.add('aspell-nl');

fpsystem('/bin/rm -rf /tmp/packages.list');

for i:=0 to l.Count-1 do begin
     if not libs.RPM_is_application_installed(l.Strings[i]) then begin
          f:=f + ',' + l.Strings[i];
     end;
end;



 result:=f;
end;
//#########################################################################################

function tcentos.CheckPDNS():string;
var
   l:TstringList;
   f:string;
   i:integer;
begin
l:=Tstringlist.Create;
l.add('pdns');
l.add('pdns-recursor');
l.add('boost-devel');
l.add('lua-devel');

for i:=0 to l.Count-1 do begin
     if not libs.RPM_is_application_installed(l.Strings[i]) then begin
          f:=f + ',' + l.Strings[i];
     end;
end;
 result:=f;
 l.free;

end;
//#########################################################################################
function tcentos.CheckCyrus():string;
var
   l:TstringList;
   f:string;
   i:integer;

begin
f:='';
l:=TstringList.Create;
l.Add('cyrus-imapd');
l.Add('cyrus-imapd-perl');
l.add('net-snmp-devel');


for i:=0 to l.Count-1 do begin
     if not libs.RPM_is_application_installed(l.Strings[i]) then begin
          f:=f + ',' + l.Strings[i];
     end;
end;
 result:=f;
 l.free;
end;
//#########################################################################################
function tcentos.CheckBasePHP():string;
var
   l:TstringList;
   f:string;
   i:integer;
   distri:tdistriDetect;
   UbuntuIntVer:integer;
   libs:tlibs;

begin
f:='';
l:=TstringList.Create;
distri:=tdistriDetect.Create();
libs:=tlibs.Create;

// --enablerepo=centosplus
l.add('httpd-devel');
if not FileExists('/etc/artica-postfix/NO_DATABASES_ENGINES') then L.add('openldap-devel');
l.add('expat-devel'); //expat.h
l.add('freetype-devel'); // ftconfig.h
l.add('libgcrypt-devel'); //gcrypt.h
l.add('gd-devel'); //gdcache.h
l.add('gmp-devel'); //gmp.h
//jpegint.h match pas
l.add('krb5-devel'); //gssapi_krb5.h
l.add('libmcrypt-devel'); //mcrypt.h
l.add('libmhash-devel'); //mhash.h
l.add('mysql-devel'); //mysql.h
l.add('ncurses-devel'); //curses.h
l.add('pam-devel'); //pam_ext.h
l.add('pcre-devel'); //pcre.h
l.add('libpng-devel'); //png.h
l.add('postgresql-devel'); //postgresql/c.h match pas
l.add('aspell-devel'); //pspell.h
l.add('recode-devel'); //recode.h
l.add('cyrus-sasl-devel'); //sasl.h
l.add('sqlite-devel'); //sqlite.h
l.add('openssl-devel'); //libcrypto.a
//l.add('t1lib-devel'); //t1lib.h
l.add('libtidy-devel');//libtidy.a ,tify.h match pas
l.add('libtool'); //libtool
l.add('tcp_wrappers'); //libwrap.a ,tcpd.h
//libxmlparse.a,libxmlparse.so ,xmlparse.h
l.add('libxml2-devel'); //libxml2.a,libxml2.a
l.add('libxslt-devel'); //libexslt.a
//bin/quilt match pas
l.add('re2c');//bin/re2c
l.add('unixODBC-devel');//sql.h
l.add('zlib-devel');//zlib.h
L.add('chrpath'); //bin/chrpath
l.add('freetds-devel'); //sybdb.h

l.add('libc-client-devel');//c-client/smtp.h
l.add('curl-devel'); //curl.h
l.add('net-snmp-devel'); //agent_callbacks.h


for i:=0 to l.Count-1 do begin
     if not libs.RPM_is_application_installed(l.Strings[i]) then begin
          f:=f + ',' + l.Strings[i];
     end;
end;
 result:=f;


end;
//#########################################################################################
function tcentos.checkSamba():string;
var
   l:TstringList;
   f:string;
   i:integer;

begin
f:='';
fpsystem('touch /etc/artica-postfix/samba.check.time');
l:=TstringList.Create;
l.Add('nss_ldap');
l.Add('samba');
l.Add('samba-client');
l.Add('pam_smb');
l.Add('nscd');
l.add('cups-devel');
l.add('gimp-print-cups');
l.add('gtk2-devel');
l.add('libtiff-devel');
l.add('libjpeg-devel');
l.add('e2fsprogs-devel');
l.add('pam-devel');
L.add('acl');
if IsRPMForgeSelected then  L.add('BackupPC');
if IsRPMForgeSelected then  l.add('par2cmdline');
l.add('nmap');
l.add('audit');


for i:=0 to l.Count-1 do begin
     if not libs.RPM_is_application_installed(l.Strings[i]) then begin
          f:=f + ',' + l.Strings[i];
     end;
end;
 result:=f;
 l.free;
end;
//#########################################################################################
function tcentos.CheckDevcollectd():string;
var
   l:TstringList;
   f:string;
   i:integer;

begin
f:='';
l:=TstringList.Create;
l.Add('iproute-dev');
l.Add('xfslibs-dev');
l.Add('librrd2-dev');
l.Add('libsensors-dev');
l.Add('libmysqlclient15-dev');
l.Add('libperl5.8');
L.add('xmms-dev');
L.add('xmms2-dev');
l.add('libesmtp-dev');
l.add('libnotify-dev');
l.add('libxml2-dev');
l.add('libpcap-dev');
l.add('hddtemp');
l.add('mbmon');
l.add('libconfig-general-perl');
l.Add('memcached');
for i:=0 to l.Count-1 do begin
     if not libs.RPM_is_application_installed(l.Strings[i]) then begin
          f:=f + ',' + l.Strings[i];
     end;
end;
 result:=f;
 l.free;
end;



function tcentos.checkSQuid():string;
var
   l:TstringList;
   f:string;
   i:integer;

begin
f:='';
l:=TstringList.Create;
l.Add('squid');
l.Add('awstats');

for i:=0 to l.Count-1 do begin
     if not libs.RPM_is_application_installed(l.Strings[i]) then begin
          f:=f + ',' + l.Strings[i];
     end;
end;
 result:=f;
 l.free;
end;
//########################################################################################
function tcentos.checkApps(l:tstringlist):string;
var
   f:string;
   i:integer;

begin
f:='';
for i:=0 to l.Count-1 do begin
     if not libs.RPM_is_application_installed(l.Strings[i]) then begin
          f:=f + ',' + l.Strings[i];
     end;
end;
 result:=f;
 l.free;
end;

//##############################################################################
function tcentos.Explode(const Separator, S: string; Limit: Integer = 0):TStringDynArray;
var
  SepLen       : Integer;
  F, P         : PChar;
  ALen, Index  : Integer;
begin
  SetLength(Result, 0);
  if (S = '') or (Limit < 0) then
    Exit;
  if Separator = '' then
  begin
    SetLength(Result, 1);
    Result[0] := S;
    Exit;
  end;
  SepLen := Length(Separator);
  ALen := Limit;
  SetLength(Result, ALen);

  Index := 0;
  P := PChar(S);
  while P^ <> #0 do
  begin
    F := P;
    P := StrPos(P, PChar(Separator));
    if (P = nil) or ((Limit > 0) and (Index = Limit - 1)) then
      P := StrEnd(F);
    if Index >= ALen then
    begin
      Inc(ALen, 5); // mehrere auf einmal um schneller arbeiten zu können
      SetLength(Result, ALen);
    end;
    SetString(Result[Index], F, P - F);
    Inc(Index);
    if P^ <> #0 then
      Inc(P, SepLen);
  end;
  if Index < ALen then
    SetLength(Result, Index); // wirkliche Länge festlegen
end;
//#########################################################################################
procedure tcentos.DennouRuby();
begin
exit;
SetCurrentDir('/etc/yum.repos.d');
fpsystem('cd /etc/yum.repos.d/');
fpsystem('wget http://centos.karan.org/kbsingh-CentOS-Extras.repo');
fpsystem('wget http://ruby.gfd-dennou.org/products/rpm/RPMS/CentOS/CentOS-DennouRuby.repo');
fpsystem('yum -y --enablerepo=kbs-CentOS-Testing install ruby bitmap-fonts ruby-bdb ruby-cairo');
end;
//#########################################################################################

function tcentos.RPMFORGE():boolean;
var
   u:string;
   link:string;
    MAJOR:integer;
    MINOR:integer;
    distri:tdistriDetect;
    filename:string;
begin
   distri:=tdistriDetect.Create();
   MAJOR:=distri.DISTRI_MAJOR;
   MINOR:=distri.DISTRI_MINOR;
   writeln('Checking.............: Base: Code CENTOS ('+distri.DISTRINAME_VERSION+') MAJOR='+IntToStr(MAJOR) ,' MINOR=',MINOR);

   result:=false;
   if not libs.RPM_is_application_installed('rpmforge-release') then begin
   writeln('Some mandatories packages need to turn you distribution into:');
   writeln('          ****************       ');
   writeln('              rpmForge           ');
   writeln('          ****************       ');
   writeln('');
   writeln('');
   writeln('Do want to make this operation ?[Y]');
   readln(u);
   if length(u)=0 then u:='Y';
   if lowercase(trim(u))<>'y' then begin
      writeln('Operation canceled: "',lowercase(trim(u)),'"');
      exit;

   end;

   writeln('Checking.............: retrieve rpmforge-release');
   if ARCH=64 then begin
      if MINOR>3 then begin
         link:='http://rpmforge.sw.be/redhat/el5/en/x86_64/rpmforge/RPMS/rpmforge-release-0.5.1-1.el5.rf.x86_64.rpm';
         filename:='rpmforge-release-0.5.1-1.el5.rf.x86_64.rpm';
      end;
//      if MINOR>5 then link:='http://tree.repoforge.org/redhat/el6/en/x86_64/rpmforge/RPMS/rpmforge-release-0.5.2-2.el6.rf.x86_64.rpm';
   end;
   if ARCH=32 then begin
       if MINOR>3 then begin
          link:='http://rpmforge.sw.be/redhat/el5/en/i386/rpmforge/RPMS/rpmforge-release-0.5.1-1.el5.rf.i386.rpm';
          filename:='rpmforge-release-0.5.1-1.el5.rf.i386.rpm';
       end;
       //if MINOR>5 then link:='http://tree.repoforge.org/redhat/el6/en/i386/rpmforge/RPMS/rpmforge-release-0.5.2-2.el6.rf.i686.rpm';
   end;
   fpsystem('wget '+link);
   fpsystem('rpm -iv '+filename);
   fpsystem('/bin/rm -rf /tmp/packages.list');
   if not libs.RPM_is_application_installed('rpmforge-release') then begin
      writeln('Unable to install rpmforge-release');
      exit;
   end;

   fpsystem('rpm --import http://apt.sw.be/RPM-GPG-KEY.dag.txt');
   fpsystem('yum check-update');
   end;



   if not IsRPMForgeAsked() then begin
       writeln('Some required packages need to turn you distribution into:');
       writeln('          ****************       ');
       writeln('        atrpms, epel,elrepo');
       writeln('          ****************       ');
       writeln('');
       writeln('');
       writeln('Do want to make this operation ?[N]');
       readln(u);
        if length(u)=0 then u:='N';
        if lowercase(trim(u))<>'y' then begin
           fpsystem('/bin/touch /tmp/IsNotRPMForge');
           exit;
        end;
        fpsystem('/bin/touch /tmp/IsRPMForge');
        EPEL();
        ELREPO();
        ATRPMS();
   end;

   

end;
//#########################################################################################
function tcentos.ATRPMS():boolean;
var u,uri:string;

begin
   result:=false;
   if Fileexists('/etc/smart/channels/atrpms.channel') then exit(true);
   if libs.RPM_is_application_installed('atrpms-package-config') then exit(true);

   writeln('Checking.............: retrieve atrpms Architecture: ',ARCH);


   if ARCH=32 then fpsystem('rpm -iv http://dl.atrpms.net/el5-i386/atrpms/stable/atrpms-package-config-120-3.el5.i386.rpm');
   if ARCH=64 then fpsystem('rpm -iv http://dl.atrpms.net/el5-x86_64/atrpms/stable/atrpms-package-config-120-3.el5.x86_64.rpm');

   fpsystem('/bin/rm -rf /tmp/packages.list');
   if not libs.RPM_is_application_installed('atrpms-package-config') then begin
      writeln('Unable to install atrpms');
      exit;
   end;

   fpsystem('rpm --import http://packages.atrpms.net/RPM-GPG-KEY.atrpms');


   fpsystem('yum check-update');
   exit(true);
end;
//#########################################################################################
function tcentos.ELREPO():boolean;
var u,uri:string;

begin
   result:=false;
   if libs.RPM_is_application_installed('elrepo-release') then exit(true);
   writeln('Checking.............: retrieve elrepo Architecture: ',ARCH);

   fpsystem('rpm -Uvh http://elrepo.org/elrepo-release-0.1-1.el5.elrepo.noarch.rpm');


   fpsystem('/bin/rm -rf /tmp/packages.list');
   if not libs.RPM_is_application_installed('elrepo-release') then begin
      writeln('Unable to install elrepo');
      exit;
   end;

   fpsystem('rpm --import http://elrepo.org/RPM-GPG-KEY-elrepo.org');


   fpsystem('yum check-update');
   exit(true);
end;
//#########################################################################################
function tcentos.EPEL():boolean;
begin
if libs.RPM_is_application_installed('epel-release') then exit(true);
   writeln('Checking.............: retrieve epel-release');

   if ARCH=64 then fpsystem('rpm -Uvh http://download.fedora.redhat.com/pub/epel/5/x86_64/epel-release-5-4.noarch.rpm');
   if ARCH=32 then fpsystem('rpm -Uvh http://download.fedora.redhat.com/pub/epel/5/i386/epel-release-5-4.noarch.rpm');

   fpsystem('rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL');
   fpsystem('yum check-update');
  if not libs.RPM_is_application_installed('epel-release') then begin
      writeln('Unable to install epel-release');
      exit;
   end;
   fpsystem('/bin/rm -rf /tmp/packages.list');
   exit(true);
end;
end.
