<?php
// Installed by the nextcloud package. Nextcloud merges every config/*.config.php
// into config.php and does not write to this file. Local changes are kept on
// package updates.
$CONFIG = [
	// The shipped apps belong to the package and are read-only. Apps from the
	// app store go to custom_apps/, which the web server user can write. The
	// same split as in the official Docker images.
	'apps_paths' => [
		[
			'path' => '/var/www/html/nextcloud/apps',
			'url' => '/apps',
			'writable' => false,
		],
		[
			'path' => '/var/www/html/nextcloud/custom_apps',
			'url' => '/custom_apps',
			'writable' => true,
		],
	],
	// The package manager updates Nextcloud. The web updater would overwrite
	// files that belong to the package, and the package does not ship it.
	'upgrade.disable-web' => true,
];
