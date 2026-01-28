# jenkins8000.pp (Puppet 5.5 compatible)
#
# Supported OS:
# - Ubuntu 20.04/22.04
# - RHEL/Rocky/Alma 8/9
#
# Purpose:
# - Install Jenkins + Java
# - Force Jenkins to listen on designated port 8000 - Can be any port you choose, no checks for currently in use ports as not in the requirements ;)
# - Optional (toggle): show Jenkins initial unlock token in a nice message :)

# -------------------------
# Variables you may change
# -------------------------
$jenkins_port    = 8000
$jenkins_java    = '/usr/bin/java'
$jenkins_war     = '/usr/share/java/jenkins.war'
$jenkins_webroot = '/var/cache/jenkins/war'

# Set to false to disable showing the initial unlock token in Puppet output.
$show_jenkins_unlock = false

# Where Jenkins writes the initial unlock token
$jenkins_unlock_file = '/var/lib/jenkins/secrets/initialAdminPassword'

$osfam = $facts['os']['family']

service { 'jenkins':
  ensure => running,
  enable => true,
}

if $osfam == 'Debian' {

  # ---- Debian / Ubuntu ----

  package { ['ca-certificates', 'curl', 'gnupg', 'fontconfig']:
    ensure => installed,
  }

  # Jenkins repo key + repo (2026 key)
  file { '/etc/apt/keyrings':
    ensure => directory,
    mode   => '0755',
  }

  exec { 'jenkins_repo_key_debian':
    command => '/usr/bin/curl -fsSL -o /etc/apt/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key',
    path    => ['/usr/bin', '/bin'],
    creates => '/etc/apt/keyrings/jenkins-keyring.asc',
    require => [Package['curl'], File['/etc/apt/keyrings']],
  }

  file { '/etc/apt/sources.list.d/jenkins.list':
    ensure  => file,
    mode    => '0644',
    content => "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/\n",
    require => Exec['jenkins_repo_key_debian'],
    notify  => Exec['apt_update'],
  }

  exec { 'apt_update':
    command     => '/usr/bin/apt-get update',
    path        => ['/usr/bin', '/bin'],
    refreshonly => true,
  }

  package { 'openjdk-17-jre-headless':
    ensure  => installed,
    require => Exec['apt_update'],
  }

  package { 'jenkins':
    ensure  => installed,
    require => [Exec['apt_update'], Package['openjdk-17-jre-headless']],
  }

  # ---- Force port via systemd ExecStart override (authoritative) ----
  file { '/etc/systemd/system/jenkins.service.d':
    ensure  => directory,
    mode    => '0755',
    require => Package['jenkins'],
  }

  $override_content = "[Service]\nExecStart=\nExecStart=${jenkins_java} -Djava.awt.headless=true -jar ${jenkins_war} --webroot=${jenkins_webroot} --httpPort=${jenkins_port}\n"

  file { '/etc/systemd/system/jenkins.service.d/override.conf':
    ensure  => file,
    mode    => '0644',
    content => $override_content,
    require => File['/etc/systemd/system/jenkins.service.d'],
    notify  => Exec['systemd_daemon_reload_debian'],
  }

  exec { 'systemd_daemon_reload_debian':
    command     => '/bin/systemctl daemon-reload',
    path        => ['/bin', '/usr/bin'],
    refreshonly => true,
    notify      => Service['jenkins'],
  }

  Service['jenkins'] {
    require => Package['jenkins'],
  }

} elsif $osfam == 'RedHat' {

  # ---- RHEL / Rocky / Alma ----

  # gnupg2 is needed because we use gpg to check the key fingerprint
  # firewalld is used to open the Jenkins port for remote access
  package { ['ca-certificates', 'curl', 'fontconfig', 'gnupg2', 'firewalld']:
    ensure => installed,
  }

  # Ensure firewalld is running
  service { 'firewalld':
    ensure => running,
    enable => true,
  }

  exec { 'download_jenkins_key_redhat':
    command => '/usr/bin/curl -fsSL -o /etc/pki/rpm-gpg/RPM-GPG-KEY-jenkins https://pkg.jenkins.io/rpm-stable/jenkins.io-2026.key',
    path    => ['/usr/bin', '/bin'],
    require => Package['curl'],
    unless  => '/bin/sh -c "test -f /etc/pki/rpm-gpg/RPM-GPG-KEY-jenkins && gpg --quiet --with-fingerprint /etc/pki/rpm-gpg/RPM-GPG-KEY-jenkins 2>/dev/null | grep -q \"6366 7EE7 4BBA 1F0A 08A6 9872 5BA3 1D57 EF59 75CA\" "',
  }

  exec { 'import_jenkins_key_redhat':
    command     => '/usr/bin/rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-jenkins',
    path        => ['/usr/bin', '/bin', '/usr/sbin', '/sbin'],
    refreshonly => true,
    subscribe   => Exec['download_jenkins_key_redhat'],
  }

  yumrepo { 'jenkins':
    baseurl  => 'https://pkg.jenkins.io/rpm-stable',
    descr    => 'Jenkins-stable',
    enabled  => 1,
    gpgcheck => 1,
    gpgkey   => 'file:///etc/pki/rpm-gpg/RPM-GPG-KEY-jenkins',
    require  => Exec['import_jenkins_key_redhat'],
    notify   => Exec['dnf_makecache'],
  }

  exec { 'dnf_makecache':
    command     => '/usr/bin/dnf -y makecache',
    path        => ['/usr/bin', '/bin', '/usr/sbin', '/sbin'],
    refreshonly => true,
  }

  package { 'java-17-openjdk-headless':
    ensure  => installed,
    require => Exec['dnf_makecache'],
  }

  package { 'jenkins':
    ensure  => installed,
    require => [Exec['dnf_makecache'], Package['java-17-openjdk-headless']],
  }

  # ---- Force port via systemd override on RHEL-family too ----
  # On some Rocky/RHEL installs the unit hardcodes --httpPort=8080, ignoring /etc/sysconfig/jenkins.
  file { '/etc/systemd/system/jenkins.service.d':
    ensure  => directory,
    mode    => '0755',
    require => Package['jenkins'],
  }

  $override_content_rh = "[Service]\nExecStart=\nExecStart=${jenkins_java} -Djava.awt.headless=true -jar ${jenkins_war} --webroot=${jenkins_webroot} --httpPort=${jenkins_port}\n"

  file { '/etc/systemd/system/jenkins.service.d/override.conf':
    ensure  => file,
    mode    => '0644',
    content => $override_content_rh,
    require => File['/etc/systemd/system/jenkins.service.d'],
    notify  => Exec['systemd_daemon_reload_redhat'],
  }

  exec { 'systemd_daemon_reload_redhat':
    command     => '/bin/systemctl daemon-reload',
    path        => ['/bin', '/usr/bin'],
    refreshonly => true,
    notify      => Service['jenkins'],
  }

  # ---- Open firewall for Jenkins port (RHEL-family) ----
  exec { 'firewalld_open_jenkins_port':
    command => "/bin/sh -c 'firewall-cmd --permanent --add-port=${jenkins_port}/tcp && firewall-cmd --reload'",
    path    => ['/bin', '/usr/bin', '/usr/sbin', '/sbin'],
    require => Service['firewalld'],
    unless  => "/bin/sh -c 'firewall-cmd --list-ports | tr \" \" \"\\n\" | grep -qx \"${jenkins_port}/tcp\"'",
  }

  Service['jenkins'] {
    require => Package['jenkins'],
  }

} else {
  fail("Unsupported OS family: ${osfam}. Supported: Debian/Ubuntu and RedHat family.")
}

# ---- Optional unlock output (single place; applies to all OSes) ----
# Kept out of OS blocks so it isn't duplicated.
if $show_jenkins_unlock {
  exec { 'show_jenkins_unlock_token':
    command => "/bin/sh -c 'if [ -f \"${jenkins_unlock_file}\" ]; then echo \"Jenkins setup:\"; echo \"  URL:    http://localhost:${jenkins_port}/login\"; echo -n \"  Unlock: \"; cat \"${jenkins_unlock_file}\"; echo; echo \"  Note:   Disable via \\$show_jenkins_unlock=false\"; else echo \"Jenkins setup: unlock token not available yet (${jenkins_unlock_file}).\"; echo \"Disable via \\$show_jenkins_unlock=false\"; fi'",
    path    => ['/bin', '/usr/bin'],
    require => Service['jenkins'],
  }
}

