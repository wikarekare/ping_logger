#Round robin log of pings to hosts. Grows, only if hosts are added.
CREATE TABLE `pinglog` (
  `ping_id` int(11) NOT NULL,
  `ping_time` datetime DEFAULT NULL,
  `host_name` char(64) NOT NULL,
  `ping` enum('T','F') DEFAULT NULL,
  `time1` float(7,3) DEFAULT NULL,
  `time2` float(7,3) DEFAULT NULL,
  `time3` float(7,3) DEFAULT NULL,
  `time4` float(7,3) DEFAULT NULL,
  `time5` float(7,3) DEFAULT NULL,
  KEY `ping_id` (`ping_id`),
  KEY `ping_time` (`ping_time`),
  KEY `host_name` (`host_name`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

#Ping index is being replaced with a round robin sequence in the sequence table.
#See mysql_seqence at https://github.com/wikarekare/mysql_sequence
CREATE TABLE `lastping` (
  `hostname` char(64) NOT NULL DEFAULT '',
  `ping_time` datetime DEFAULT NULL,
  PRIMARY KEY (`hostname`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

#Might be needed, if not already there.
CREATE TABLE `sequence` (
  `name` varchar(50) NOT NULL,
  `initial_value` int(10) unsigned NOT NULL DEFAULT '1',
  `current_value` int(10) unsigned NOT NULL DEFAULT '0',
  `step_size` int(10) unsigned NOT NULL DEFAULT '1',
  `max_value` int(10) unsigned NOT NULL DEFAULT '4294967295',
  `cycle` tinyint(4) NOT NULL DEFAULT '0',
  PRIMARY KEY (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=latin;
