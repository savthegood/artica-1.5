<?php

class os_system_datas{
	
	function part_type_array(){
		$part_type["01"]="DOS 12-bit fat";
		$part_type["02"]="XENIX root";
		$part_type["03"]="XENIX /usr";
		$part_type["04"]="DOS 3.0+ 16-bit FAT (up to 32M)";
		$part_type["05"]="DOS 3.3+ Extended Partition";
		$part_type["06"]="DOS 3.31+ 16-bit FAT (over 32M)";
		$part_type["07"]="OS/2 IFS (e.g., HPFS)";
		$part_type["07"]="Advanced Unix";
		$part_type["07"]="Windows NT NTFS";
		$part_type["07"]="QNX2.x (pre-1988)";
		$part_type["08"]="OS/2 (v1.0-1.3 only)";
		$part_type["08"]="AIX boot partition";
		$part_type["08"]="SplitDrive";
		$part_type["08"]="DELL partition spanning multiple drives";
		$part_type["08"]="Commodore DOS";
		$part_type["08"]="QNX 1.x and 2.x (qny)";
		$part_type["09"]="AIX data partition";
		$part_type["09"]="Coherent filesystem";
		$part_type["09"]="QNX 1.x and 2.x (qnz)";
		$part_type["0a"]="OS/2 Boot Manager";
		$part_type["0a"]="Coherent swap partition";
		$part_type["0a"]="OPUS";
		$part_type["0b"]="WIN95 OSR2 32-bit FAT";
		$part_type["0c"]="WIN95 OSR2 32-bit FAT, LBA-mapped";
		$part_type["0e"]="WIN95: DOS 16-bit FAT, LBA-mapped";
		$part_type["0f"]="WIN95: Extended partition, LBA-mapped";
		$part_type["10"]="OPUS (?)";
		$part_type["11"]="Hidden DOS 12-bit FAT";
		$part_type["12"]="Compaq config partition";
		$part_type["14"]="Hidden DOS 16-bit FAT <32M";
		$part_type["16"]="Hidden DOS 16-bit FAT >=32M";
		$part_type["17"]="Hidden IFS (e.g., HPFS)";
		$part_type["18"]="AST SmartSleep Partition";
		$part_type["19"]="Unused (Claimed for Willowtech Photon COS)";
		$part_type["1b"]="Hidden WIN95 OSR2 32-bit FAT";
		$part_type["1c"]="Hidden WIN95 OSR2 32-bit FAT, LBA-mapped";
		$part_type["1e"]="Hidden WIN95 16-bit FAT, LBA-mapped";
		$part_type["20"]="Unused";
		$part_type["21"]="Reserved";
		$part_type["21"]="Unused";
		$part_type["22"]="Unused";
		$part_type["23"]="Reserved";
		$part_type["24"]="NEC DOS 3.x";
		$part_type["26"]="Reserved";
		$part_type["31"]="Reserved";
		$part_type["32"]="NOS";
		$part_type["33"]="Reserved";
		$part_type["34"]="Reserved";
		$part_type["35"]="JFS on OS/2 or eCS";
		$part_type["36"]="Reserved";
		$part_type["38"]="THEOS ver 3.2 2gb partition";
		$part_type["39"]="Plan 9 partition";
		$part_type["39"]="THEOS ver 4 spanned partition";
		$part_type["3a"]="THEOS ver 4 extended partition";
		$part_type["41"]="Personal RISC Boot";
		$part_type["41"]="PPC PReP (Power PC Reference Platform) Boot";
		$part_type["42"]="Linux swap (sharing disk with DRDOS)";
		$part_type["42"]="SFS (Secure Filesystem)";
		$part_type["42"]="Windows 2000 marker";
		$part_type["43"]="Linux native (sharing disk with DRDOS)";
		$part_type["44"]="GoBack partition";
		$part_type["45"]="Boot-US boot manager";
		$part_type["45"]="Priam";
		$part_type["45"]="EUMEL/Elan";
		$part_type["46"]="EUMEL/Elan";
		$part_type["47"]="EUMEL/Elan";
		$part_type["4"]="EUMEL/Elan";
		$part_type["4a"]="AdaOS Aquila (Default)";
		$part_type["4a"]="ALFS/THIN lightweight filesystem for DOS";
		$part_type["4c"]="Oberon partition";
		$part_type["4d"]="QNX4.x";
		$part_type["4e"]="QNX4.x 2nd part";
		$part_type["4f"]="QNX4.x 3rd part";
		$part_type["4f"]="Oberon partition";
		$part_type["50"]="OnTrack Disk Manager (older versions) RO";
		$part_type["50"]="Lynx RTOS";
		$part_type["50"]="Native Oberon (alt)";
		$part_type["51"]="OnTrack Disk Manager RW (DM6 Aux1)";
		$part_type["51"]="Novell";
		$part_type["52"]="CP/M";
		$part_type["52"]="Microport SysV/AT";
		$part_type["53"]="Disk Manager 6.0 Aux3";
		$part_type["54"]="Disk Manager 6.0 Dynamic Drive Overlay";
		$part_type["55"]="EZ-Drive";
		$part_type["56"]="Golden Bow VFeature Partitioned Volume.";
		$part_type["56"]="DM converted to EZ-BIOS";
		$part_type["57"]="DrivePro";
		$part_type["57"]="VNDI Partition";
		$part_type["5c"]="Priam EDisk";
		$part_type["61"]="SpeedStor";
		$part_type["63"]="Unix System V (SCO, ISC Unix, UnixWare, ...), Mach, GNU Hurd";
		$part_type["64"]="PC-ARMOUR protected partition";
		$part_type["64"]="Novell Netware 286, 2.xx";
		$part_type["65"]="Novell Netware 386, 3.xx or 4.xx";
		$part_type["66"]="Novell Netware SMS Partition";
		$part_type["67"]="Novell";
		$part_type["68"]="Novell";
		$part_type["69"]="Novell Netware 5+, Novell Netware NSS Partition";
		$part_type["70"]="DiskSecure Multi-Boot";
		$part_type["71"]="Reserved";
		$part_type["73"]="Reserved";
		$part_type["74"]="Reserved";
		$part_type["74"]="Scramdisk partition";
		$part_type["75"]="IBM PC/IX";
		$part_type["76"]="Reserved";
		$part_type["77"]="M2FS/M2CS partition";
		$part_type["77"]="VNDI Partition";
		$part_type["78"]="XOSL FS";
		$part_type["80"]="MINIX until 1.4a";
		$part_type["81"]="Linux";
		$part_type["81"]="Mitac disk manager";
		$part_type["82"]="Prime";
		$part_type["82"]="Solaris x86";
		$part_type["82"]="Linux swap";
		$part_type["83"]="Linux native";
		$part_type["84"]="OS/2 hidden C: drive";
		$part_type["84"]="Hibernation partition";
		$part_type["85"]="Linux extended partition";
		$part_type["86"]="Old Linux RAID partition superblock";
		$part_type["86"]="NTFS volume set";
		$part_type["87"]="NTFS volume set";
		$part_type["8a"]="Linux Kernel Partition (used by AiR-BOOT)";
		$part_type["8b"]="Legacy Fault Tolerant FAT32 volume";
		$part_type["8c"]="Legacy Fault Tolerant FAT32 volume using BIOS extd INT 13h";
		$part_type["8d"]="Free FDISK hidden Primary DOS FAT12 partitition";
		$part_type["8e"]="Linux Logical Volume Manager partition";
		$part_type["90"]="Free FDISK hidden Primary DOS FAT16 partitition";
		$part_type["91"]="Free FDISK hidden DOS extended partitition";
		$part_type["92"]="Free FDISK hidden Primary DOS large FAT16 partitition";
		$part_type["93"]="Hidden Linux native partition";
		$part_type["93"]="Amoeba";
		$part_type["94"]="Amoeba bad block table";
		$part_type["95"]="MIT EXOPC native partitions";
		$part_type["97"]="Free FDISK hidden Primary DOS FAT32 partitition";
		$part_type["98"]="Free FDISK hidden Primary DOS FAT32 partitition (LBA)";
		$part_type["99"]="DCE376 logical drive";
		$part_type["9a"]="Free FDISK hidden Primary DOS FAT16 partitition (LBA)";
		$part_type["9b"]="Free FDISK hidden DOS extended partitition (LBA)";
		$part_type["9f"]="BSD/OS";
		$part_type["a0"]="Laptop hibernation partition";
		$part_type["a1"]="Laptop hibernation partition";
		$part_type["a1"]="HP Volume Expansion (SpeedStor variant)";
		$part_type["a8"]="Mac OS-X";
		$part_type["a9"]="NetBSD";
		$part_type["aa"]="Olivetti Fat 12 1.44Mb Service Partition";
		$part_type["ab"]="Mac OS-X Boot partition";
		$part_type["ab"]="GO! partition";
		$part_type["ae"]="ShagOS filesystem";
		$part_type["af"]="ShagOS swap partition";
		$part_type["b0"]="BootStar Dummy";
		$part_type["b1"]="Reserved";
		$part_type["b3"]="Reserved";
		$part_type["b4"]="Reserved";
		$part_type["b6"]="Reserved";
		$part_type["b7"]="BSDI BSD/386 filesystem";
		$part_type["b8"]="BSDI BSD/386 swap partition";
		$part_type["bb"]="Boot Wizard hidden";
		$part_type["be"]="Solaris 8 boot partition";
		$part_type["c0"]="CTOS";
		$part_type["c0"]="REAL/32 secure small partition";
		$part_type["c0"]="NTFT Partition";
		$part_type["c1"]="DRDOS/secured (FAT-12)";
		$part_type["c2"]="Reserved for DR-DOS 7+";
		$part_type["c2"]="Hidden Linux";
		$part_type["c3"]="Hidden Linux swap";
		$part_type["c4"]="DRDOS/secured (FAT-16, < 32M)";
		$part_type["c5"]="DRDOS/secured (extended)";
		$part_type["c6"]="DRDOS/secured (FAT-16, >= 32M)";
		$part_type["c6"]="Windows NT corrupted FAT16 volume/stripe set";
		$part_type["c7"]="Windows NT corrupted NTFS volume/stripe set";
		$part_type["c7"]="Syrinx boot";
		$part_type["c8"]="(See also ID c2.)";
		$part_type["c9"]="(See also ID c2.)";
		$part_type["ca"]="(See also ID c2.)";
		$part_type["cb"]="reserved for DRDOS/secured (FAT32)";
		$part_type["cc"]="reserved for DRDOS/secured (FAT32, LBA)";
		$part_type["cd"]="CTOS Memdump?";
		$part_type["ce"]="reserved for DRDOS/secured (FAT16, LBA)";
		$part_type["d0"]="REAL/32 secure big partition";
		$part_type["d1"]="Old Multiuser DOS secured FAT12";
		$part_type["d4"]="Old Multiuser DOS secured FAT16 <32M";
		$part_type["d5"]="Old Multiuser DOS secured extended partition";
		$part_type["d6"]="Old Multiuser DOS secured FAT16 >=32M";
		$part_type["d8"]="CP/M-86";
		$part_type["da"]="Non-FS Data";
		$part_type["db"]="Digital Research CP/M, Concurrent CP/M, Concurrent DOS";
		$part_type["db"]="CTOS (Convergent Technologies OS -Unisys)";
		$part_type["db"]="KDG Telemetry SCPU boot";
		$part_type["dd"]="Hidden CTOS Memdump?";
		$part_type["de"]="Dell PowerEdge Server utilities (FAT fs)";
		$part_type["df"]="DG/UX virtual disk manager partition";
		$part_type["df"]="BootIt EMBRM";
		$part_type["e0"]="Reserved by STMicroelectronics for a filesystem called ST AVFS.";
		$part_type["e1"]="DOS access or SpeedStor 12-bit FAT extended partition";
		$part_type["e3"]="DOS R/O or SpeedStor";
		$part_type["e4"]="SpeedStor 16-bit FAT extended partition < 1024 cyl.";
		$part_type["e5"]="Tandy DOS with logical sectored FAT (According to Powerquest.)";
		$part_type["e5"]="Reserved";
		$part_type["e6"]="Reserved";
		$part_type["eb"]="BFS (aka BeFS)";
		$part_type["ed"]="Reserved for Matthias Paul’s Sprytix";
		$part_type["ee"]="Indication that this legacy MBR is followed by an EFI header";
		$part_type["ef"]="Partition that contains an EFI file system";
		$part_type["f0"]="Linux/PA-RISC boot loader";
		$part_type["f1"]="SpeedStor";
		$part_type["f2"]="DOS 3.3+ secondary partition (Powerquest writes: Unisys DOS with logical sectored FAT.)";
		$part_type["f3"]="Reserved    (Powerquest writes: Storage Dimensions SpeedStor.)";
		$part_type["f4"]="SpeedStor large partition";
		$part_type["f4"]="Prologue single-volume partition";
		$part_type["f5"]="Prologue multi-volume partition";
		$part_type["f6"]="Reserved (Powerquest writes: Storage Dimensions SpeedStor. )";
		$part_type["fa"]="Bochs";
		$part_type["fb"]="VMware File System partition";
		$part_type["fc"]="VMware Swap partition";
		$part_type["fd"]="Linux raid partition with autodetect using persistent superblock (Powerquest writes: Reserved for FreeDOS. )";
		$part_type["fe"]="SpeedStor > 1024 cyl.";
		$part_type["fe"]="LANstep";
		$part_type["fe"]="IBM PS/2 IML (Initial Microcode Load) partition, located at the end of the disk.";
		$part_type["fe"]="Windows NT Disk Administrator hidden partition";
		$part_type["fe"]="Linux Logical Volume Manager partition (old)";
		$part_type["ff"]="Xenix Bad Block Table";
		return $part_type;
	}
	
}
?>