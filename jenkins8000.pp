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

  # ---- Force port via systemd ExecStart override (authoritative on Ubuntu 22.04) ----
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
    notify  => Exec['systemd_daemon_reload'],
  }

  exec { 'systemd_daemon_reload':
    command     => '/bin/systemctl daemon-reload',
    path        => ['/bin', '/usr/bin'],
    refreshonly => true,
    notify      => Service['jenkins'],
  }

  Service['jenkins'] {
    require => Package['jenkins'],
  }

  # ---- Tidy optional unlock output (single notify; no exec spam) ----
  if $show_jenkins_unlock {
    if file($jenkins_unlock_file) {
      notify { 'jenkins_setup':
        message => "Jenkins setup:\n  URL:    http://localhost:${jenkins_port}/login\n  Unlock: ${file($jenkins_unlock_file)}\n  Note:   Disable via \$show_jenkins_unlock=false",
        require => Service['jenkins'],
      }
    } else {
      notify { 'jenkins_setup_pending':
        message => "Jenkins setup: unlock token not available yet (${jenkins_unlock_file}). Jenkins may still be initializing.\nDisable via \$show_jenkins_unlock=false",
        require => Service['jenkins'],
      }
    }
  }

} elsif $osfam == 'RedHat' {

  # ---- RHEL / Rocky / Alma ----

  package { ['ca-certificates', 'curl', 'fontconfig']:
    ensure => installed,
  }

  exec { 'download_jenkins_key_redhat':
    command => '/usr/bin/curl -fsSL -o /etc/pki/rpm-gpg/RPM-GPG-KEY-jenkins https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key',
    path    => ['/usr/bin', '/bin'],
    creates => '/etc/pki/rpm-gpg/RPM-GPG-KEY-jenkins',
    require => Package['curl'],
  }

  exec { 'import_jenkins_key_redhat':
    command => '/usr/bin/rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-jenkins',
    path    => ['/usr/bin', '/bin', '/usr/sbin', '/sbin'],
    require => Exec['download_jenkins_key_redhat'],
    unless  => '/bin/sh -c "rpm -q gpg-pubkey --qf \"%{SUMMARY}\n\" | grep -qi jenkins || true"',
  }

  yumrepo { 'jenkins':
    baseurl  => 'https://pkg.jenkins.io/redhat-stable',
    descr    => 'Jenkins-stable',
    enabled  => 1,
    gpgcheck => 1,
    gpgkey   => 'file:///etc/pki/rpm-gpg/RPM-GPG-KEY-jenkins',
    require  => [Exec['import_jenkins_key_redhat'], Exec['download_jenkins_key_redhat']],
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

  exec { 'set_jenkins_port_redhat':
    command => "/bin/sh -c 'if grep -qE \"^JENKINS_PORT=\" /etc/sysconfig/jenkins; then sed -i \"s/^JENKINS_PORT=.*/JENKINS_PORT=${jenkins_port}/\" /etc/sysconfig/jenkins; else echo \"JENKINS_PORT=${jenkins_port}\" >> /etc/sysconfig/jenkins; fi'",
    path    => ['/usr/bin', '/bin'],
    require => Package['jenkins'],
    unless  => "/bin/sh -c 'grep -qE \"^JENKINS_PORT=${jenkins_port}$\" /etc/sysconfig/jenkins'",
    notify  => Service['jenkins'],
  }

  Service['jenkins'] {
    require => Package['jenkins'],
  }

  # ---- Tidy optional unlock output (single notify; no exec spam) ----
  if $show_jenkins_unlock {
    if file($jenkins_unlock_file) {
      notify { 'jenkins_setup_rh':
        message => "Jenkins setup:\n  URL:    http://localhost:${jenkins_port}/login\n  Unlock: ${file($jenkins_unlock_file)}\n  Note:   Disable via \$show_jenkins_unlock=false",
        require => Service['jenkins'],
      }
    } else {
      notify { 'jenkins_setup_pending_rh':
        message => "Jenkins setup: unlock token not available yet (${jenkins_unlock_file}). Jenkins may still be initializing.\nDisable via \$show_jenkins_unlock=false",
        require => Service['jenkins'],
      }
    }
  }

} else {
  fail("Unsupported OS family: ${osfam}. Supported: Debian/Ubuntu and RedHat family.")
}
