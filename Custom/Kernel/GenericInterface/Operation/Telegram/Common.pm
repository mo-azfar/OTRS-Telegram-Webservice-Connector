# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::GenericInterface::Operation::Telegram::Common;

use strict;
use warnings;

use MIME::Base64();
use Net::CIDR::Set;
use JSON::MaybeXS;
use LWP::UserAgent;
use HTTP::Request::Common;

use Kernel::System::VariableCheck qw(:all);

our $ObjectManagerDisabled = 1;

sub ValidateTelegramIP {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    return if !$Param{REMOTE_ADDR};
        
    my $TelegramServer = Net::CIDR::Set->new( '149.154.160.0/20', '91.108.4.0/22' );
    my $AllowedServer;
    
    if ( $TelegramServer->contains( $Param{REMOTE_ADDR} ) ) 
    {
    $AllowedServer = $Param{REMOTE_ADDR};
    return $AllowedServer;
    }
    else 
    {
	return;
    }
    
} 

sub ValidateTelegramUser {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    return if !$Param{User};

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $ChatIDField = $ConfigObject->Get('GenericInterface::Operation::TicketTelegram')->{'ChatIDField'};
    my $UserObject = $Kernel::OM->Get('Kernel::System::User');
        
    #search user based on telegram chat id
    my %List = $UserObject->SearchPreferences(
        Key   => $ChatIDField,
        Value => $Param{User},   # optional, limit to a certain value/pattern
    );
    
    if ( !%List ) {
        return;
    }
    
    #get user id based on telegram chat id
    my $AgentID;
    for my $UserID ( keys %List )
    {
        my %Users = $UserObject->GetUserData(
        UserID => $UserID,
        Valid  => 1,       # not required -> 0|1 (default 0)
                                # returns only data if user is valid
        );
    
        $AgentID = $Users{'UserID'};
        last if $Param{User} eq $Users{$ChatIDField};
    }
    
    if ( !$AgentID ) {
        return;
    }
    
    return $AgentID;
    
} 

sub ValidateCommand {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    return if !$Param{Command};
    
    if ( $Param{Command} ne "chatid" && $Param{Command} ne "get" && $Param{Command} ne "help" && $Param{Command} ne "mine" && $Param{Command} ne "addnote")
    {
        return;
    }
    
    return $Param{Command};
    
} 

sub GetTicket {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    return if !$Param{TicketID};
    
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    
    my $HttpType = $ConfigObject->Get('HttpType');
	my $FQDN = $ConfigObject->Get('FQDN');
	my $ScriptAlias = $ConfigObject->Get('ScriptAlias');
    
    my %NoAccess;
    my $Access = $TicketObject->TicketPermission(
        Type     => 'ro',
        TicketID => $Param{TicketID},
        UserID   => $Param{UserID},
    );
        
    if ( !$Access ) 
    {
            $NoAccess{GetText} = "Error: Need RO Permissions";
            $NoAccess{TicketURL} = $HttpType.'://'.$FQDN.'/'.$ScriptAlias.'index.pl?Action=AgentTicketZoom;TicketID=0';
            $NoAccess{TicketNumber} = "No Permission";
            return %NoAccess;
    
    }
    
    my %Ticket = $TicketObject->TicketGet(
        TicketID      => $Param{TicketID},
        DynamicFields => 0,         
        UserID        => 1,
        Silent        => 0,         
    );
    
    my %OwnerName =  $Kernel::OM->Get('Kernel::System::User')->GetUserData(
        UserID => $Ticket{OwnerID},
    );
    
    my %RespName =  $Kernel::OM->Get('Kernel::System::User')->GetUserData(
        UserID => $Ticket{ResponsibleID},
    );
    
    my $GetText = "
    - *Type*: $Ticket{Type}
    - *Created*: $Ticket{Created}
    - *State*: $Ticket{State} 
    - *Queue*: $Ticket{Queue}
    - *Owner*: $OwnerName{UserFullname}
    - *Resposible*: $RespName{UserFullname}
    - *Priority*: $Ticket{Priority}
    - *Service*: $Ticket{Service}
    - *SLA*: $Ticket{SLA}";

    my $TicketURL = $HttpType.'://'.$FQDN.'/'.$ScriptAlias.'index.pl?Action=AgentTicketZoom;TicketID='.$Param{TicketID};
    $Ticket{GetText} = $GetText;
    $Ticket{TicketURL} = $TicketURL;
    return %Ticket;
    
} 

sub MyOwner {
    my ( $Self, %Param ) = @_;

    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
     
    # check needed stuff
    return if !$Param{AgentID};
    
    my $HttpType = $ConfigObject->Get('HttpType');
	my $FQDN = $ConfigObject->Get('FQDN');
	my $ScriptAlias = $ConfigObject->Get('ScriptAlias');
    
    my @OwnerTicketIDs = $TicketObject->TicketSearch(
        Result => 'ARRAY',
        StateType    => ['open', 'new', 'pending reminder', 'pending auto'],
        OwnerIDs => [$Param{AgentID}],
        UserID => 1,
        );
        
    my $OwnerText;
    if (@OwnerTicketIDs)
    {
        $OwnerText = "Ticket Owner Under Your Account: \n\n";
        foreach my $OwnTicketID (@OwnerTicketIDs)
        {
            my %OwnTicket = $TicketObject->TicketGet(
            TicketID      => $OwnTicketID,
            DynamicFields => 0,         
            UserID        => 1,
            Silent        => 0,         
            );
            my $TicketURL = $HttpType.'://'.$FQDN.'/'.$ScriptAlias.'index.pl?Action=AgentTicketZoom;TicketID='.$OwnTicketID;
            $OwnerText .= "[Ticket#$OwnTicket{TicketNumber}]($TicketURL) - $OwnTicket{Title}\n";
            
        }
    }
    else
    {
        $OwnerText = "No Ticket Owner Assigned To You";
    }
    
    return $OwnerText;
    
} 

sub MyResponsible {
    my ( $Self, %Param ) = @_;

    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    
    # check needed stuff
    return if !$Param{AgentID};
    
    my $HttpType = $ConfigObject->Get('HttpType');
	my $FQDN = $ConfigObject->Get('FQDN');
	my $ScriptAlias = $ConfigObject->Get('ScriptAlias');
    
    my @ResponsibleTicketIDs = $TicketObject->TicketSearch(
        Result => 'ARRAY',
        StateType    => ['open', 'new', 'pending reminder', 'pending auto'],
        ResponsibleIDs => [$Param{AgentID}],
        UserID => 1,
        );
        
    my $ResponsibleText;
    if (@ResponsibleTicketIDs)
    {
        $ResponsibleText = "Ticket Responsible Under Your Account: \n\n";
        foreach my $ResponsibleTicketID (@ResponsibleTicketIDs)
        {
            my %ResponsibleTicket = $TicketObject->TicketGet(
            TicketID      => $ResponsibleTicketID,
            DynamicFields => 0,         
            UserID        => 1,
            Silent        => 0,         
            );
            my $TicketURL = $HttpType.'://'.$FQDN.'/'.$ScriptAlias.'index.pl?Action=AgentTicketZoom;TicketID='.$ResponsibleTicketID;
            $ResponsibleText .= "[Ticket#$ResponsibleTicket{TicketNumber}]($TicketURL) - $ResponsibleTicket{Title}\n";
        }
    }
    else
    {
        $ResponsibleText = "No Ticket Responsible Assigned To You";
    
    }
    
    return $ResponsibleText;
} 

sub AddNote {
    my ( $Self, %Param ) = @_;
    
    # check needed stuff
    return if !$Param{TicketID};
    return if !$Param{AgentID};
    return if !$Param{Body};
    
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my $ArticleBackendObject = $Kernel::OM->Get('Kernel::System::Ticket::Article')->BackendForChannel(ChannelName => 'Internal');
    
    my $Access = $TicketObject->TicketPermission(
        Type     => 'note',
        TicketID => $Param{TicketID},
        UserID   => $Param{AgentID},
        );
    
    if ( !$Access ) 
    {
        return "Error: Need Note Permissions";
    }
            
    my %FullName =  $Kernel::OM->Get('Kernel::System::User')->GetUserData(
        UserID => $Param{AgentID},
    );
    
    my $ArticleID = $ArticleBackendObject->ArticleCreate(
		TicketID             => $Param{TicketID},                              # (required)
		SenderType           => 'agent',                          # (required) agent|system|customer
		IsVisibleForCustomer => 0,                                # (required) Is article visible for customer?
		UserID               => $Param{AgentID},                              # (required)
		From           => $FullName{UserFullname},       # not required but useful
		#To             => 'Helpdesk', # not required but useful
		Subject        => "Note from $FullName{UserFullname} via Telegram",               # not required but useful
		Body           => $Param{Body},                     # not required but useful
		ContentType    => 'text/plain; charset=ISO-8859-15',      # or optional Charset & MimeType
		HistoryType    => 'AddNote',                          # EmailCustomer|Move|AddNote|PriorityUpdate|WebRequestCustomer|...
		HistoryComment => 'Add note from Telegram',
		NoAgentNotify    => 0,                                      # if you don't want to send agent notifications
    );

    if (!$ArticleID)
    {
        return "Error: Something Wrong";
    }
    
    return "Success";

}

sub SentMessage {
    
    my ( $Self, %Param ) = @_;
    
    # check needed stuff
    return if !$Param{Text};
    return if !$Param{ChatID};
    return if !$Param{MsgID};
    
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $Token = $ConfigObject->Get('GenericInterface::Operation::TicketTelegram')->{'Token'};
    
    my $ua = LWP::UserAgent->new;
    my $p = {
            chat_id => $Param{ChatID},
            parse_mode => 'Markdown',
            reply_to_message_id => $Param{MsgID},
            text => $Param{Text}, 
            };
            
    my $response = $ua->request(
        POST "https://api.telegram.org/bot".$Token."/sendMessage",
        Content_Type    => 'application/json',
        Content         => JSON::MaybeXS::encode_json($p)
        );
        
    my $ResponseData = $Kernel::OM->Get('Kernel::System::JSON')->Decode(
        Data => $response->decoded_content,
    );
    
    my $msg;
    if ($ResponseData->{ok} eq 0)
    {
        $msg= "Telegram notification to $Param{ChatID}: $ResponseData->{description}",
        
    }
    else
    {
        $msg="Sent Telegram to $Param{ChatID}: $Param{Text}";
    }
    
    return $msg;
    
}
1;
