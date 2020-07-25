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

sub MyTicket {
    my ( $Self, %Param ) = @_;

    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
     
    # check needed stuff
    return if !$Param{AgentID};
    return if !$Param{Condition};
    
    my $HttpType = $ConfigObject->Get('HttpType');
	my $FQDN = $ConfigObject->Get('FQDN');
	my $ScriptAlias = $ConfigObject->Get('ScriptAlias');
    
    my @OwnerTicketIDs = $TicketObject->TicketSearch(
        Result => 'ARRAY',
        StateType    => \@{$Param{Condition}},
        OwnerIDs => [$Param{AgentID}],
        UserID => 1,
        );
        
    #use for telegram dynamic keyboard
    my @TicketData = ();
    
    if (@OwnerTicketIDs)
    {
        foreach my $OwnTicketID (@OwnerTicketIDs)
        {
            my %OwnTicket = $TicketObject->TicketGet(
            TicketID      => $OwnTicketID,
            DynamicFields => 0,         
            UserID        => 1,
            Silent        => 0,         
            );
            
            my $TicketURL = $HttpType.'://'.$FQDN.'/'.$ScriptAlias.'index.pl?Action=AgentTicketZoom;TicketID='.$OwnTicketID;
            
            #use for telegram dynamic keyboard
            push @TicketData, [{ 
				text => "[O] Ticket#$OwnTicket{TicketNumber}", 
				callback_data => "/get/$OwnTicketID",
			},
            { 
				text => "Portal", 
                url => $TicketURL,
			}];
            
        }
    }
    
    my @ResponsibleTicketIDs = $TicketObject->TicketSearch(
        Result => 'ARRAY',
        StateType    => \@{$Param{Condition}},
        ResponsibleIDs => [$Param{AgentID}],
        UserID => 1,
    );
    
    if (@ResponsibleTicketIDs)
    {
        foreach my $ResponsibleTicketID (@ResponsibleTicketIDs)
        {
            my %ResponsibleTicket = $TicketObject->TicketGet(
            TicketID      => $ResponsibleTicketID,
            DynamicFields => 0,         
            UserID        => 1,
            Silent        => 0,         
            );
            
            my $TicketURL = $HttpType.'://'.$FQDN.'/'.$ScriptAlias.'index.pl?Action=AgentTicketZoom;TicketID='.$ResponsibleTicketID;
            
            #use for telegram dynamic keyboard
            push @TicketData, [{ 
				text => "[R] Ticket#$ResponsibleTicket{TicketNumber}", 
				callback_data => "/get/$ResponsibleTicketID",
			},
            { 
				text => "Portal", 
                url => $TicketURL,
			}];
        }
    }
    
    push @TicketData, [{ 
        text => "Menu", 
        callback_data => "/menu",
        }];
    
    return @TicketData;
    
}

sub GetTicket {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    return if !$Param{TicketID};
    return if !$Param{AgentID};
    
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    
    my $HttpType = $ConfigObject->Get('HttpType');
	my $FQDN = $ConfigObject->Get('FQDN');
	my $ScriptAlias = $ConfigObject->Get('ScriptAlias');
    
    ##Check permission just in case user no longer an owner or resposible (by clicking previous ticket menu)
    my $Access = $TicketObject->TicketPermission(
        Type     => 'ro',
        TicketID => $Param{TicketID},
        UserID   => $Param{AgentID},
    );
    
    if ( !$Access ) 
    {
        my $NoAccess = "Error: Need RO Permissions";
        return $NoAccess;
    }
    
    my %Ticket = $TicketObject->TicketGet(
        TicketID      => $Param{TicketID},
        DynamicFields => 0,         
        UserID        => $Param{AgentID},
        Silent        => 0,         
    );
    
    my %OwnerName =  $Kernel::OM->Get('Kernel::System::User')->GetUserData(
        UserID => $Ticket{OwnerID},
    );
    
    my %RespName =  $Kernel::OM->Get('Kernel::System::User')->GetUserData(
        UserID => $Ticket{ResponsibleID},
    );
    
    my $GetText = "<b>OTRS#$Ticket{TicketNumber}</b>
    
    - <b>Type</b>: $Ticket{Type}
    - <b>Created</b>: $Ticket{Created}
    - <b>State</b>: $Ticket{State} 
    - <b>Queue</b>: $Ticket{Queue}
    - <b>Owner</b>: $OwnerName{UserFullname}
    - <b>Resposible</b>: $RespName{UserFullname}
    - <b>Priority</b>: $Ticket{Priority}
    - <b>Service</b>: $Ticket{Service}
    - <b>SLA</b>: $Ticket{SLA}";
    
    #if push back to ticket api, make sure the request is hash %.
    #$Ticket{GetText} = $GetText;
  
    return ($GetText, $Ticket{TicketNumber});
    
} 

 
sub AddNote {
    my ( $Self, %Param ) = @_;
    
    # check needed stuff
    return if !$Param{TicketID};
    return if !$Param{AgentID};
    return if !$Param{Body};
    
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my $ArticleBackendObject = $Kernel::OM->Get('Kernel::System::Ticket::Article')->BackendForChannel(ChannelName => 'Internal');
    
    ##Check permission just in case user no longer an owner or resposible (by clicking previous ticket menu)
    my $Access = $TicketObject->TicketPermission(
        Type     => 'note',
        TicketID => $Param{TicketID},
        UserID   => $Param{AgentID},
    );
    
    if ( !$Access ) 
    {
        my $NoAccess = "Error: Need Note Permissions";
        return $NoAccess;
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
            parse_mode => 'HTML',
            #reply_to_message_id => $Param{MsgID},
            text => $Param{Text},
            reply_markup => {
				#resize_keyboard => \1, # \1 = true when JSONified, \0 = false
                inline_keyboard => \@{$Param{Keyboard}}, #telegram dynamic keyboard
                force_reply => $Param{Force},
                selective => $Param{Selective}
				}
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
