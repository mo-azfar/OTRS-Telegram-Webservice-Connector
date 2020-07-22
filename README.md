# OTRS-Telegram-Webservice-Connector  
- Built for OTRS CE v6.0  
- This module enable the integration from Telegram users (as an agent) to OTRS.  
- by conversation with a bot, agent can get a list of their ticket, add note, etc.  
- **Available upon request**

	Used CPAN module
	
	Encode qw(decode encode);
	Digest::MD5 qw(md5_hex);
	Date::Parse;
	Data::Dumper;
	MIME::Base64();
	Net::CIDR::Set;
	JSON::MaybeXS;
	LWP::UserAgent;
	HTTP::Request::Common;  
	

1. Create a telegram bot and get a bot token

2. Update telegram webhook to point to otrs REST Webservices  
    
    	https://api.telegram.org/bot<BOT_TOKEN>/setWebhook?url=https://<SERVERNAME>/otrs/nph-genericinterface.pl/Webservice/GenericTicketConnectorREST/TicketTelegram/?UserLogin=webservice;Password=123otrs

 
3. As per url, its point to /TicketTelegram/ connector with user and password assign to them. webservice user should at least have ro permision.


4. In OTRS, Go to Webservice (REST), Add operation Telegram::TicketTelegram  
  
	Name: TicketTelegram  
  
5. Configure REST Network Trasnport  

  	*Route mapping for Operation 'TicketTelegram': /TicketTelegram/  
  	*Method: POST  


6. Update System Configuration > GenericInterface::Operation::TicketTelegram###ChatIDField  

  	Field name that hold the telegram chat id for agent. Default: UserComment  


7. Update System Configuration > GenericInterface::Operation::TicketTelegram###Token  

  	Update the token (get from no 1).  


8. Make sure OTRS agent has a telegram chat id under their profile ( UserComment field )

	start the conversation with the created bot (no 1) to get the chat id with the command /chatid


9. Based on connector, otrs will listen to /command/ticketnumber from telegram.

	example to get ticket details: /get/1100068


10. Rules check

	- Telegram chat id must be registered in the OTRS agent profile.
	- Only ip address from telegram server are allowed to use this connector.


11. To test the connection to telegram,

	shell > curl -X GET https://api.telegram.org/bot<TELEGRAM_BOT_TOKEN>/getMe   


Simulation

[![download-3.png](https://i.postimg.cc/QMpYjcLf/download-3.png)](https://postimg.cc/kVgvc6gS)

[![download-2.png](https://i.postimg.cc/gkTTsYqH/download-2.png)](https://postimg.cc/nCq2cfWX)

[![download-1.png](https://i.postimg.cc/Wb3y0Dr4/download-1.png)](https://postimg.cc/Hjq3gk6G)

[![download.png](https://i.postimg.cc/fLNFdBj4/download.png)](https://postimg.cc/yJLv4hbn)

[![download-4.png](https://i.postimg.cc/NMDNHYjT/download-4.png)](https://postimg.cc/DJWQ99sy)

