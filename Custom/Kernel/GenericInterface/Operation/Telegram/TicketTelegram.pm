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

    my $CacheObject = $Kernel::OM->Get('Kernel::System::Cache');
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
    
    my $CacheType = "TelegramUser";
    my $GreetText = "Please Use The Menu Below";
    my $AddNoteText = "Please enter a note for this case";
    
    #if using text command
    if ( defined $Param{Data}->{message} ) 
    {
        #verify telegram user agent based on chat id
        my $AgentID = $Self->ValidateTelegramUser(
            User => $Param{Data}->{message}->{chat}->{id},
        );
        
        if ( !$AgentID ) 
        {
            
            my @KeyboardData = ();
            
            #sent telegram
            my $Sent = $Self->SentMessage(
                ChatID => $Param{Data}->{message}->{chat}->{id},
                MsgID => $Param{Data}->{message}->{message_id},
                Text => "Opps. Your ChatID $Param{Data}->{message}->{chat}->{id} is not registered as our agent.",
                Keyboard => \@KeyboardData, #dynamic keyboard
                Force => \0, 
                Selective => \0,
            );
        
            return {
                Success => 1,
                Data    => {
                    text => $Sent,
                },
            };
        }
        
        my $CacheKeyTicketID = "TelegramUserTicketID-$Param{Data}->{message}->{chat}->{id}";
        my $CacheKeyTicketNumber = "TelegramUserTicketNumber-$Param{Data}->{message}->{chat}->{id}";
        my $CacheKeyMine = "TelegramUsermine-$Param{Data}->{message}->{chat}->{id}";
        my $Text = $Param{Data}->{message}->{text};
        my $ReplyToText = $Param{Data}->{message}->{reply_to_message}->{text} || 0;
        
        #check either this is replied text for add note param
        if ( $ReplyToText eq $AddNoteText )
        {
            #get back ticket id via cache
            my $TicketID = $CacheObject->Get(
                Type => $CacheType,
                Key  => $CacheKeyTicketID,
            ) || '';
            
            #get back ticket number via cache
            my $TicketNumber = $CacheObject->Get(
                Type => $CacheType,
                Key  => $CacheKeyTicketNumber,
            ) || '';
            
            #ticket id cache is found
            if ($TicketID)
            {
                
                my $AddNoteResult = $Self->AddNote(
                    TicketID => $TicketID,
                    AgentID => $AgentID,
                    Body => $Text,
                );
                
                #get back previous mine selection via cache or set default to menu if empty
                my $PrevMine = $CacheObject->Get(
                Type => $CacheType,
                Key  => $CacheKeyMine,
                ) || '/menu';
                
                my @KeyboardData = (
                [{ 
                    text => "Menu", 
                    callback_data => "/menu",
                },
                { 
                    text => "Go Back To List", 
                    callback_data => "$PrevMine",
                }]
                );
                
                #sent telegram
                my $Sent = $Self->SentMessage(
                    ChatID =>$Param{Data}->{message}->{chat}->{id},
                    MsgID => $Param{Data}->{message}->{message_id},
                    Text => "Add Note to Ticket Number <b>OTRS#$TicketNumber ($TicketID):</b> 
$AddNoteResult",
                    Keyboard => \@KeyboardData, #dynamic keyboard
                    Force => \0, 
                    Selective => \0, 
                );
                
                return {
                    Success => 1,
                    Data    => {
                        text => $Sent,
                    },
                };
            }
            
            else
            {
                
                my @KeyboardData = (
                [{ 
                    text => "Get WIP Ticket", 
                    callback_data => "/mine/wip",
                },
                { 
                    text => "Get Resolved Ticket", 
                    callback_data => "/mine/closed",
                }]
                );
                
                #sent telegram
                my $Sent = $Self->SentMessage(
                    ChatID =>$Param{Data}->{message}->{chat}->{id},
                    MsgID => $Param{Data}->{message}->{message_id},
                    Text => "Oooops..timeout. Please try again",
                    Keyboard => \@KeyboardData, #dynamic keyboard
                    Force => \0, 
                    Selective => \0, 
                );
                
                return {
                    Success => 1,
                    Data    => {
                        text => $Sent,
                    },
                };
            }
            
        }
        
        else
        {
        
            my @KeyboardData = (
            [{ 
				text => "Get WIP Ticket", 
				callback_data => "/mine/wip",
			},
            { 
				text => "Get Resolved Ticket", 
				callback_data => "/mine/closed",
			}]
            );
                
            #sent telegram
            my $Sent = $Self->SentMessage(
                ChatID =>$Param{Data}->{message}->{chat}->{id},
                MsgID => $Param{Data}->{message}->{message_id},
                Text => $GreetText,
                Keyboard => \@KeyboardData, #dynamic keyboard
                Force => \0, 
                Selective => \0, 
            );
            
            return {
                Success => 1,
                Data    => {
                    text => $Sent,
                },
            };
        }
        
    } #end if using text command
    
    #if using callback button from SentMessageKeyboard
    elsif ( defined $Param{Data}->{callback_query} ) 
    {
       
        #verify telegram user agent based on chat id
        my $AgentID = $Self->ValidateTelegramUser(
            User => $Param{Data}->{callback_query}->{message}->{chat}->{id},
        );
        
        if ( !$AgentID ) 
        {
            
            my @KeyboardData = ();
            
            #sent telegram
            my $Sent = $Self->SentMessage(
                ChatID => $Param{Data}->{callback_query}->{message}->{chat}->{id},
                MsgID => $Param{Data}->{callback_query}->{message}->{message_id},
                Text => "Opps. Your ChatID $Param{Data}->{callback_query}->{message}->{chat}->{id} is not registered as our agent.",
                Keyboard => \@KeyboardData, #dynamic keyboard
                Force => \0, 
                Selective => \0,
            );
        
            return {
                Success => 1,
                Data    => {
                    text => $Sent,
                },
            };
        }
        
        my $CacheKeyMine = "TelegramUsermine-$Param{Data}->{callback_query}->{message}->{chat}->{id}";
        my $CacheKeyTicketID = "TelegramUserTicketID-$Param{Data}->{callback_query}->{message}->{chat}->{id}";
        my $CacheKeyTicketNumber = "TelegramUserTicketNumber-$Param{Data}->{callback_query}->{message}->{chat}->{id}";
         
        #menu
        if ($Param{Data}->{callback_query}->{data} eq "/menu")
        {
            my @KeyboardData = (
            [{ 
				text => "Get WIP Ticket", 
				callback_data => "/mine/wip",
			},
            { 
				text => "Get Resolved Ticket", 
				callback_data => "/mine/closed",
			}]
            );
                
            #sent telegram
            my $Sent = $Self->SentMessage(
                ChatID => $Param{Data}->{callback_query}->{message}->{chat}->{id},
                MsgID => $Param{Data}->{callback_query}->{message}->{message_id},
                Text => $GreetText,
                Keyboard => \@KeyboardData, #dynamic keyboard
                Force => \0, 
                Selective => \0, 
            );
            
            return {
                Success => 1,
                Data    => {
                    text => $Sent,
                },
            };
        }
        
        ##check ticket
        elsif ($Param{Data}->{callback_query}->{data} eq "/mine/wip" || $Param{Data}->{callback_query}->{data} eq "/mine/closed")
        {
           
            my @PossibleStateType = ();
            my $SelectedCMD;
            
            if ($Param{Data}->{callback_query}->{data} eq "/mine/wip")
            {
                @PossibleStateType = ('new', 'open', 'pending reminder', 'pending auto'); 
                $SelectedCMD = "<b>Work in Progress Case</b>";
            }
            elsif ($Param{Data}->{callback_query}->{data} eq "/mine/closed")
            {
                @PossibleStateType = ('closed'); 
                $SelectedCMD = "<b>Resolved Case</b>";
            }
            
            #delete cache if exist (for selected mine button)
            $CacheObject->Delete(
                Type => $CacheType,       # only [a-zA-Z0-9_] chars usable
                Key  => $CacheKeyMine,
            );
            
            #create cache for selected mine button
            $CacheObject->Set(
                Type  => $CacheType,
                Key   => $CacheKeyMine,
                Value => $Param{Data}->{callback_query}->{data} || '',
                TTL   => 10 * 60, #set cache (means cache for 10 minutes)
            );
            
            #check total ticket
            my @TotalKeyboard = $Self->MyTicket(
                AgentID => $AgentID,
                Condition => \@PossibleStateType,
            );
            
            #sent telegram
            my $Sent = $Self->SentMessage(
                ChatID => $Param{Data}->{callback_query}->{message}->{chat}->{id},
                MsgID => $Param{Data}->{callback_query}->{message}->{message_id},
                Text =>  $SelectedCMD,
                Keyboard => \@TotalKeyboard, #dynamic keyboard list based of number of ticket (ticket id, ticket number) found in api above.
                Force => \0, 
                Selective => \0,
            );
            
        
            return {
                Success => 1,
                Data    => {
                    text => "$Sent",
                },
            };
        }
        
        #check ticket details
        elsif ($Param{Data}->{callback_query}->{data} =~ "^/get/")
        {
        
            my @gettid = split '/', $Param{Data}->{callback_query}->{data};
            my $tid = $gettid[2];
            
            #get ticket details
            my ($getTicket, $TN) = $Self->GetTicket(
                TicketID => $tid,
                AgentID => $AgentID,
            );
            
            #get back previous mine selection via cache or set default to menu if empty
            my $PrevMine = $CacheObject->Get(
                Type => $CacheType,
                Key  => $CacheKeyMine,
            ) || '/menu';
        
            my @KeyboardData = (
            [{ 
				text => "Add Note", 
				callback_data => "/addnote/$tid/$TN",
			}],
            [{ 
				text => "Menu", 
				callback_data => "/menu",
			},
            { 
				text => "Go back To List", 
				callback_data => "$PrevMine",
			}],
            );
            
            #sent telegram
            my $Sent = $Self->SentMessage(
                ChatID => $Param{Data}->{callback_query}->{message}->{chat}->{id},
                MsgID => $Param{Data}->{callback_query}->{message}->{message_id},
                Text => $getTicket,
                Keyboard => \@KeyboardData, #dynamic keyboard
                Force => \0, 
                Selective => \0,
            );
        
            return {
                Success => 1,
                Data    => {
                    text => $Sent,
                },
            };
        }
        
        #add note
        elsif ($Param{Data}->{callback_query}->{data} =~ "^/addnote/")
        {
        
            my @gettid = split '/', $Param{Data}->{callback_query}->{data};
            my $tid = $gettid[2];
            my $tn = $gettid[3];
            
            #delete tid cache if exist
            my $DeleteCache1 = $CacheObject->Delete(
                Type => $CacheType,       # only [a-zA-Z0-9_] chars usable
                Key  => $CacheKeyTicketID,
            );
            
            #delete tn cache if exist
            my $DeleteCache2 = $CacheObject->Delete(
                Type => $CacheType,       # only [a-zA-Z0-9_] chars usable
                Key  => $CacheKeyTicketNumber,
            );
            
            #create cache for ticket id
            my $SetCache1 = $CacheObject->Set(
                Type  => $CacheType,
                Key   => $CacheKeyTicketID,
                Value => $tid || '',
                TTL   => 5 * 60, #set cache (means cache for 5 minutes)
            );
        
            #create cache for ticket number
            my $SetCache2 = $CacheObject->Set(
                Type  => $CacheType,
                Key   => $CacheKeyTicketNumber,
                Value => $tn|| '',
                TTL   => 5 * 60, #set cache (means cache for 5 minutes)
            );
        
            my @KeyboardData = ();
            
            #sent message after cache is set
            my $Sent1 = $Self->SentMessage(
                ChatID => $Param{Data}->{callback_query}->{message}->{chat}->{id},
                MsgID => $Param{Data}->{callback_query}->{message}->{message_id},
                Text => "Adding Note for <b>OTRS#$tn</b>..Processing Input Field..",
                Keyboard => \@KeyboardData, #dynamic keyboard
                Force => \0, 
                Selective => \0, 
            );
            
            #sent message after cache is set
            my $Sent2 = $Self->SentMessage(
                ChatID => $Param{Data}->{callback_query}->{message}->{chat}->{id},
                MsgID => $Param{Data}->{callback_query}->{message}->{message_id},
                Text => $AddNoteText,
                Keyboard => \@KeyboardData, #dynamic keyboard
                Force => \1, 
                Selective => \1, 
            );
            
            return {
                Success => 1,
                Data    => {
                    text => "$Sent1 $Sent2",
                },
            }; 
            
        }
  
    } #end if using callback button from SentMessageKeyboard
    
}

1;
