#!/usr/bin/perl -w
use strict;
use Net::Telnet;
use IO::Pty;
use POSIX;
use Getopt::Std;

my ($username, $password, $host, $cmd, @output, $line, $debug, $prompt, $pmt);
my ($pty, $ssh, @lines, $command);
our ($opt_u, $opt_p, $opt_t, $opt_h, $opt_d);

($username, $password, $host) = qw(admin xxxxxx 172.16.9.13); #Default un, password
getopts('u:p:t:c:dh:');
if ($opt_u) { $username = $opt_u }
if ($opt_p) { $password = $opt_p }
if ($opt_h) { $host     = $opt_h }
if ($opt_t) { $pmt      = $opt_t }
if ($opt_d) { $debug = 1 }

if (@ARGV) { $command = $ARGV[0];
    } else {
    print "Invalid or missing command\n";
    usage();
    exit;
}
#HELP_MESSAGE(&usage);
#usage();


#Set up an option for a prompt number.  Like 1 7x50, 2 for unix etc.
my %prmt = (
    1 => '/[\$%#>] $/',     #Default prompt
    2 => '/[A-B]:\S+#/',    #Prompt for 7x50 routers
);
if (!$pmt) {
    $prompt = $prmt{ 2 };       #set the Defautl prompt
} elsif ($pmt ge 1 && $pmt le 2) {
    $prompt = $prmt{ $pmt }
} else {
    usage();
}
###############
# main -----
login($username, $password, $host, $prompt);
send_cmd("$command");
logout();
exit 1;


sub send_cmd {
    my $cmd = shift;
    my $response = $ssh->cmd("environment no more");
        unless ($response) {print "Command failed!\n"; return 0; }
    ## Send command, get and print its output.
    my @lines = $ssh->cmd("$cmd");      #This needs some more
    print @lines;                       #Error checking
    $ssh->cmd('exit all');
    return @lines;
}

sub logout {
    my $response = '';
    #Change the prompt for logout.  Response is different.
    $ssh->prompt('/\S+.*closed/');
    $response = $ssh->cmd('logout');
    unless ($response) {print "Logout was not clean: " . $ssh->last_prompt . "\n"; return undef; }
    return 1;

}
sub login {
    my ($user, $pass, $host, $prompt) =@_;

        ## Start ssh program.
        $pty = _spawn("ssh", "-l", $user, $host);  # spawn() defined below

        ## Create a Net::Telnet object to perform I/O on ssh's tty.
        $ssh = new Net::Telnet (-fhopen => $pty,
                                -prompt => $prompt,
                            -telnetmode => 0,
                       -cmd_remove_mode => 1,
               -output_record_separator => "\r",
                               -timeout => 30,
                              );
        if ($debug) { $ssh->dump_log("errlog.txt") }

        ## Login to remote host.
        my ($preok, $ok) = $ssh->waitfor(-match => '/password: ?$/i',                     #Checking for 2 conditions
                                         -match => '/.*continue connecting (yes\/no)?/i', #Either a straight password prompt
                                       -errmode => "return")                              # or if never connected answer 'yes' to
            or die "problem connecting to host: ", $ssh->lastline;                        #SSH's question.
            
        if ($ok =~ /.*continue connecting (yes\/no)?/i) {                                 #If we got this the
            $ssh->print("yes\n");                                                         #SSH question must be answered
            print STDERR "First time logging into this host, saying yes!\n";
            $ssh->waitfor(-match => '/password: ?$/i',                                    #Wait for password prmpt
                        -errmode => "return")
            or die "No prompt from from host: ", $ssh->lastline;
            $ssh->print($pass);
            $ssh->waitfor(-match => $ssh->prompt,                                         #Wait for the regular prompt
                        -errmode => "return")
            or die "No prompt from host: ", $ssh->lastline;
        } elsif ($ok =~ /password: ?$/i) {                                  #This is normal processing
            $ssh->print($pass);
            $ssh->waitfor(-match => $ssh->prompt,
                        -errmode => "return")
            or die "login failed: ", $ssh->lastline;
        }
        return 1;
}

    sub _spawn {
        my(@cmd) = @_;
        my($pid, $pty, $tty, $tty_fd);

        ## Create a new pseudo terminal.
        $pty = new IO::Pty
            or die $!;

        ## Execute the program in another process.
        unless ($pid = fork) {  # child process
            die "problem spawning program: $!\n" unless defined $pid;

            ## Disassociate process from existing controlling terminal.
            POSIX::setsid
                or die "setsid failed: $!";

            ## Associate process with a new controlling terminal.
            $tty = $pty->slave;
            $pty->make_slave_controlling_terminal();
            $tty_fd = $tty->fileno;
            close $pty;

            ## Make stdio use the new controlling terminal.
            open STDIN, "<&$tty_fd" or die $!;
            open STDOUT, ">&$tty_fd" or die $!;
            open STDERR, ">&STDOUT" or die $!;
            close $tty;

            ## Execute requested program.
            exec @cmd
                or die "problem executing $cmd[0]\n";
        } # end child process

        $pty;
    } # end sub spawn
    
sub usage {
    print "usage: ssh-telnet.pl [-d -u <username> -p <password> -h <hostname or ip> -t [1|2] ] <command> \n";
    print "--help  This help\n";
    print "-u  username\n";
    print "-p  password\n";
    print "-h  hostname\n";
    print "-d  debug on\n";
    print "-t  prompt number, current prompts defined:\n";
    print "    1 = \'[\\\$%#>] \$\'   Default prompt\n";
    print "    2 = \'[A-B]:\\S+#\'  Prompt for 7x50 routers\n\n";
}