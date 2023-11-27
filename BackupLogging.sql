CREATE TABLE `Daily` (
  `Id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `Date` date NOT NULL DEFAULT current_timestamp(),
  `Time` time NOT NULL DEFAULT current_timestamp(),
  `Domain` varchar(30) NOT NULL,
  `Type` varchar(10) NOT NULL DEFAULT 'Unset',
  `Result` tinyint(4) NOT NULL,
  `Critical` tinyint(3) unsigned NOT NULL DEFAULT 0,
  `Message` varchar(2000) DEFAULT NULL,
  PRIMARY KEY (`Id`),
  KEY `Domain` (`Domain`)
) ENGINE=ARIA AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4

CREATE TABLE `Weekly` (
  `Id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `Date` date NOT NULL DEFAULT current_timestamp(),
  `Time` time NOT NULL DEFAULT current_timestamp(),
  `Domain` varchar(30) NOT NULL,
  `Type` varchar(10) NOT NULL DEFAULT 'Unset',
  `Result` tinyint(4) NOT NULL,
  `Critical` tinyint(3) unsigned NOT NULL DEFAULT 0,
  `Message` varchar(2000) DEFAULT NULL,
  PRIMARY KEY (`Id`),
  KEY `Domain` (`Domain`)
) ENGINE=ARIA AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4
