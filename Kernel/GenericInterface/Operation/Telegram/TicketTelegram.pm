# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::GenericInterface::Operation::Telegram::TicketTelegram;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);

use base qw(
    Kernel::GenericInterface::Operation::Common
    Kernel::GenericInterface::Operation::Telegram::Common
);

use utf8;
use Encode qw(decode encode);
use Digest::MD5 qw(md5_hex);
use Date::Parse;
use Data::Dumper;

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    # check needed objects
    for my $Needed (qw( DebuggerObject WebserviceID )) {
        if ( !$Param{$Needed} ) {

            return {
                Success      => 0,
                ErrorMessage => "Got no $Needed!"
            };
        }

        $Self->{$Needed} = $Param{$Needed};
    }

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $Token = $ConfigObject->Get('GenericInterface::Operation::TicketTelegram')->{'Token'};

    if (
        !$Param{Data}->{UserLogin}
        && !$Param{Data}->{CustomerUserLogin}
        && !$Param{Data}->{SessionID}
        )
    {
        return $Self->ReturnError(
            ErrorCode    => 'Telegram.MissingParameter',
            ErrorMessage => "Telegram: UserLogin, CustomerUserLogin or SessionID is required!",
        );
    }

    if ( $Param{Data}->{UserLogin} || $Param{Data}->{CustomerUserLogin} ) {

        if ( !$Param{Data}->{Password} )
        {
            return $Self->ReturnError(
                ErrorCode    => 'Telegram.MissingParameter',
                ErrorMessage => "Telegram: Password or SessionID is required!",
            );
        }
    }
	
    my ( $UserID, $UserType ) = $Self->Auth(
        %Param,
    );

    if ( !$UserID ) {
        return $Self->ReturnError(
            ErrorCode    => 'Telegram.AuthFail',
            ErrorMessage => "Telegram: User could not be authenticated!",
        );
    }
    
    #verify the request is from telegram server
    my $AllowedServer = $Self->ValidateTelegramIP(
        REMOTE_ADDR => $ENV{REMOTE_ADDR},
    );
    
    if ( !$AllowedServer ) {
        return $Self->ReturnError (
            ErrorCode    => 'Telegram.IPNotTelegram',
            ErrorMessage => "Telegram: Look like request IP $ENV{REMOTE_ADDR} not from telegram!",
        );
    }
    
    my $Text = $Param{Data}->{message}->{text};
    
    #text format should be /command/ticketnumber e.g: /get/123
    my @getCommand = split '/', $Text;
    my $command = $getCommand[1];
    my $tn = $getCommand[2];
    my $note = $getCommand[3];
    
    #verify command
    my $cmd = $Self->ValidateCommand(
        Command => $command,
    );
    
    if ( !$cmd )
    {
        #TODO:since the list of command can be set and view in telegram, perhaps return error instead of sending telegram if not command
        #sent telegram
        my $Sent = $Self->SentMessage(
            ChatID => $Param{Data}->{message}->{chat}->{id},
            MsgID => $Param{Data}->{message}->{message_id},
            Text => "Command $command invalid. Type /help for info",
        );
    
        return {
            Success => 1,
            Data    => {
                text => $Sent,
            },
        };
    }
   
    if ( $cmd eq "help")
    {
        
        #sent telegram
        my $Sent = $Self->SentMessage(
            ChatID => $Param{Data}->{message}->{chat}->{id},
            MsgID => $Param{Data}->{message}->{message_id},
            Text => "Format */command/ticketnumber* . Available command as below: \n
*/chatid* = To get your chat id\n
*/mine* = To get all the ticket assigned under you\n
*/get/ticketnumber* = To get the details of specific ticket\n
*/addnote/ticketnumber* = To add a note to the specific ticket\n\n
",
);
        
        return {
            Success => 1,
            Data    => {
                text => $Sent,
            },
        };
    }
    
    if ( $cmd eq "chatid")
    {
        #sent telegram
        my $Sent = $Self->SentMessage(
            ChatID => $Param{Data}->{message}->{chat}->{id},
            MsgID => $Param{Data}->{message}->{message_id},
            Text => "Your chat id is $Param{Data}->{message}->{chat}->{id}",
        );
        
        return {
            Success => 1,
            Data    => {
                text => $Sent,
            },
        };
    }
    
    #verify telegram user based on chat id
    #this placement allow non registered chat id (in otrs) user to execute chatid and help command.
    my $AgentID = $Self->ValidateTelegramUser(
        User => $Param{Data}->{message}->{chat}->{id},
    );
    
    if ( !$AgentID ) {
        return $Self->ReturnError (
            ErrorCode    => 'Telegram.NoUser',
            ErrorMessage => "Telegram: No Telegram Chat ID $Param{Data}->{message}->{chat}->{id} Defined in OTRS!",
        );
    }
    
    if ( $cmd eq "mine")
    {
   
       #check owner ticket
       my $TicketOwnerText = $Self->MyOwner(
       AgentID => $AgentID,
       );
   
       #check responsible ticket
       my $TicketResponsibleText = $Self->MyResponsible(
       AgentID => $AgentID,
       );
       
        #sent telegram
        my $Sent = $Self->SentMessage(
            ChatID => $Param{Data}->{message}->{chat}->{id},
            MsgID => $Param{Data}->{message}->{message_id},
            Text => "
$TicketOwnerText
               
$TicketResponsibleText",
        );
        
       return 
       {
           Success => 1,
           Data    => 
           {
               text => $Sent,
           },
       };
   
   }
	
    my $TicketID = $TicketObject->TicketIDLookup( TicketNumber => $tn, );
    my $ImageURL = "http://icons.iconarchive.com/icons/artua/star-wars/256/Clone-Trooper-icon.png";
    
    if ( $cmd eq "get")
    {
        if ($TicketID) 
        {
            
            my %getTicket = $Self->GetTicket(
                TicketID => $TicketID,
                UserID   => $AgentID,
            ); 
            
            #sent telegram
            my $Sent = $Self->SentMessage(
                ChatID => $Param{Data}->{message}->{chat}->{id},
                MsgID => $Param{Data}->{message}->{message_id},
                Text => "OTRS#$getTicket{TicketNumber}
$getTicket{GetText}
                    
$getTicket{TicketURL}",
            );
            
            return 
            {
                Success => 1,
                Data    => 
                {
                    text => $Sent,
                },
            };
        }
        else
        {
            
            #sent telegram
            my $Sent = $Self->SentMessage(
                ChatID => $Param{Data}->{message}->{chat}->{id},
                MsgID => $Param{Data}->{message}->{message_id},
                Text => "Error: Requested Ticket#$tn Not Found",
            );
            
            return 
            {
                Success => 1,
                Data    => 
                {
                    text => $Sent,
                },
            };
        }
    
    }
      
    if ( $cmd eq "addnote" )
    {
        if ( $TicketID && $note ne "" )
        {
            my $AddNote = $Self->AddNote(
                TicketID => $TicketID,
                AgentID => $AgentID,
                Body => $note,
            );
            
            #sent telegram
            my $Sent = $Self->SentMessage(
                ChatID => $Param{Data}->{message}->{chat}->{id},
                MsgID => $Param{Data}->{message}->{message_id},
                Text => $AddNote,
            );
            
            return 
            {
                Success => 1,
                Data    => 
                {
                    text => $Sent,
                },
            };
            
        }
        else
        {
            
            #sent telegram
            my $Sent = $Self->SentMessage(
                ChatID => $Param{Data}->{message}->{chat}->{id},
                MsgID => $Param{Data}->{message}->{message_id},
                Text => "Error: Requested Ticket#$tn Not Found or Note is Empty",
            );
            
            return 
            {
                Success => 1,
                Data    => 
                {
                    text => $Sent,
                },
            };
        }
        
    }
    
    
}

1;
