/*
 * =============================================================================
 * MOTDgd In-Game Advertisements
 * Displays MOTDgd Related In-Game Advertisements
 *
 * Copyright (C)2013-2015 MOTDgd Ltd. All rights reserved.
 * =============================================================================
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program. If not, see <http://www.gnu.org/licenses/>.
*/

// ====[ INCLUDES | DEFINES ]============================================================
#pragma semicolon 1
#include <sourcemod>
#define CHAT_TAG ""
#include <zephstocks>
#include <EasyHTTP>
#include <EasyJSON>
#include <motdgd>
#pragma newdecls required

#define STRING(%1) %1, sizeof(%1)

#define PLUGIN_VERSION "3.0.2"
 
// ====[ HANDLES | CVARS | VARIABLES ]===================================================
Handle g_serverID;
Handle g_motdID;
Handle g_OnConnect;
Handle g_immunity;
Handle g_OnOther;
Handle g_Review;
Handle g_forced;
Handle g_autoClose;
Handle g_ipOverride;
Handle g_audioOnly;
Handle g_RewardNoAd;
Handle g_RewardMode;
Handle g_RewardMsg;
Handle g_NoRewardMsg;
Handle g_NoVideoMsg;
Handle g_RewardChance;
Handle g_Cooldown;
Handle g_CooldownMsg;
Handle g_RewardEvents;
Handle g_Reminder;
Handle g_ReminderMsg;

char gameDir[255];
char g_serverIP[16];

int g_serverPort;
int g_shownTeamVGUI[MAXPLAYERS+1] = { false, ... };
int g_lastView[MAXPLAYERS+1];
int g_lastReward[MAXPLAYERS+1];
Handle g_Whitelist = INVALID_HANDLE;

bool VGUICaught[MAXPLAYERS+1];
bool CanReview;
bool LateLoad;
bool g_playerMidgame[MAXPLAYERS+1];


enum HUBState
{
	k_Closed = 0,
	k_Connected = 1,
	k_Upgrading = 2,
	k_Upgraded = 3,
	k_LoggedIn = 4
}

Handle hub = INVALID_HANDLE;
char sid[64];
HUBState hubState = k_Closed;
int ServerID = -1;
int pingInterval = -1;
int pingTimeout = -1;
Handle pingTimer = INVALID_HANDLE;
Handle timeoutTimer = INVALID_HANDLE;

Handle handlers = INVALID_HANDLE;
Handle rewards = INVALID_HANDLE;
Handle rewardWeights = INVALID_HANDLE;
int totalWeight = 0;
int shouldReward[MAXPLAYERS+1];
int g_bClientDisabledMotd[MAXPLAYERS + 1];
float reconnectDelay = 0.1;
Handle g_RemindTimer = INVALID_HANDLE;

// ====[ PLUGIN | FORWARDS ]========================================================================
public const Plugin myinfo =
{
	name = "MOTDgd Adverts",
	author = "Blackglade, Ixel, Zephyrus & Glubbable",
	description = "Displays MOTDgd In-Game Advertisements",
	version = PLUGIN_VERSION,
	url = "http://motdgd.com"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	EasyHTTP_MarkNatives();
	CreateNative("MOTDgd_AddRewardHandler", Native_AddRewardHandler);
	CreateNative("MOTDgd_RemoveRewardHandler", Native_RemoveRewardHandler);
	return APLRes_Success;
}

public void OnPluginStart()
{
	IdentifyGame();

	if (g_bL4D || g_bL4D2 || g_bND)
	{

	}

	// Global Server Variables //
	//new bool:exists = false;
	GetGameFolderName(gameDir, sizeof(gameDir));
	/*for (new i = 0; i < sizeof(g_GamesSupported); i++)
	{
		if (StrEqual(g_GamesSupported[i], gameDir))
		{
			exists = true;
			break;
		}
	}
	if (!exists)
		SetFailState("The game '%s' isn't currently supported by the MOTDgd plugin!", gameDir);
	exists = false;*/
	
	// Plugin ConVars //
	CreateConVar("sm_motdgd_version", PLUGIN_VERSION, "[SM] MOTDgd Plugin Version", FCVAR_DONTRECORD);
	g_serverID = CreateConVar("sm_motdgd_serverid", "-1", "[SM] MOTDgd Current Server ID", FCVAR_DONTRECORD);

	g_motdID = CreateConVar("sm_motdgd_userid", "0", "MOTDgd User ID. This number can be found at: https://portal.motdgd.com");
	g_immunity = CreateConVar("sm_motdgd_immunity", "0", "Enable/Disable advert immunity");
	g_OnConnect = CreateConVar("sm_motdgd_onconnect", "1", "Enable/Disable advert on connect");

	if (!StrEqual(gameDir, "tf"))
	{
		g_autoClose = CreateConVar("sm_motdgd_auto_close", "0.0", "Set time (in seconds) to automatically close the MOTD window.", _, true, 50.0);
	}

	g_ipOverride = CreateConVar("sm_motdgd_ip", "", "Your server IP. Use this if your server IP is not identified properly automatically.");
	// Global Server Variables //
	
	g_audioOnly = CreateConVar("sm_motdgd_midgame_audio_only", "0", "Set to 1 if you only want audio ads mid-game. This doesn't affect the ad shown upon connection.");


	if (!StrEqual(gameDir, "left4dead2") && !StrEqual(gameDir, "left4dead"))
	{
		HookEventEx("arena_win_panel", Event_End);
		HookEventEx("cs_win_panel_round", Event_End);
		HookEventEx("dod_round_win", Event_End);
		HookEventEx("player_death", Event_Death);
		HookEventEx("round_start", Event_Start);
		HookEventEx("round_win", Event_End);
		HookEventEx("teamplay_win_panel", Event_End);
		
		g_OnOther = CreateConVar("sm_motdgd_onother", "2", "Set 0 to disable, 1 to show on round end, 2 to show on player death, 4 to show on round start, 3=1+2, 5=1+4, 6=2+4, 7=1+2+4");
		g_Review = CreateConVar("sm_motdgd_review", "15.0", "Set time (in minutes) to re-display the ad. ConVar sm_motdgd_onother must be configured", _, true, 10.0);
	}

	if (!StrEqual(gameDir, "left4dead2") && !StrEqual(gameDir, "left4dead") && !StrEqual(gameDir, "csgo") && !StrEqual(gameDir, "csco"))
	{
		g_forced = CreateConVar("sm_motdgd_forced_duration", "5", "Number of seconds to force an ad view for (except in CS:GO, L4D, L4D2)");
	}

	g_RewardNoAd = CreateConVar("sm_motdgd_reward_on_no_ad", "0", "Give a reward even when a video is unavailable");
	g_RewardMode = CreateConVar("sm_motdgd_reward_mode", "2", "0=disabled 1=all 2=random reward with equal probabilities 3=random reward with weighted probabilities");
	g_RewardChance = CreateConVar("sm_motdgd_reward_chance", "1.0", "Chance of receiving a reward, 1.0 = 100%");
	g_RewardMsg = CreateConVar("sm_motdgd_reward_message", "Thanks for supporting us! Here's your reward!", "Message to be displayed when an ad was shown");
	g_NoVideoMsg = CreateConVar("sm_motdgd_no_video_message", "Sorry, no video was available. Try again later!", "Message to be displayed when no ad was shown");
	g_NoRewardMsg = CreateConVar("sm_motdgd_no_reward_message", "There's no reward for you this time, try again later!", "Message to be displayed when no reward was given");
	g_ReminderMsg = CreateConVar("sm_motdgd_reminder_message", "Don't forget to watch an ad for a reward! Type /ad in chat!", "Message to remind users about rewards");
	g_Reminder = CreateConVar("sm_motdgd_reminder", "5.0", "Time (in minutes) between the reminders. 0 = disabled");
	g_Cooldown = CreateConVar("sm_motdgd_cooldown", "1.0", "Minimum time (in minutes) between rewards.");
	g_CooldownMsg = CreateConVar("sm_motdgd_cooldown_message", "You have to wait another {minutes} minute(s) before you can receive another reward.", "Message to be displayed when no ad was shown");
	g_RewardEvents = CreateConVar("sm_motdgd_reward_events", "0", "Should event based ads (such as joining the game) be rewarded");
	// Plugin ConVars //

	handlers = CreateTrie();
	rewards = CreateArray(512);
	rewardWeights = CreateArray();
	RegServerCmd("sm_motdgd_add_reward", Command_AddReward);
	RegServerCmd("sm_motdgd_hub", Command_Hub);
	RegConsoleCmd("sm_ad", Command_Ad);

	// MOTDgd MOTD Stuff //
	UserMsg datVGUIMenu = GetUserMessageId("VGUIMenu");
	if (datVGUIMenu == INVALID_MESSAGE_ID)
		SetFailState("The game '%s' doesn't support VGUI menus.", gameDir);
	HookUserMessage(datVGUIMenu, OnVGUIMenu, true);
	AddCommandListener(ClosedMOTD, "closed_htmlpage");
	
	HookEventEx("player_transitioned", Event_PlayerTransitioned);
	// MOTDgd MOTD Stuff //
	
	AutoExecConfig(true);
	LoadWhitelist();

	if (LateLoad) 
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i))
				g_lastView[i] = GetTime();
		}
	}

	GetIP();

	connectHub();
}

public void OnPluginEnd() 
{
	if (hub != INVALID_HANDLE)
	{
		SocketDisconnect(hub);
	}
}

public void OnConfigsExecuted()
{
	GetIP();
	if(g_RemindTimer != INVALID_HANDLE) {
		KillTimer(g_RemindTimer);
		g_RemindTimer = INVALID_HANDLE;
	}
	g_RemindTimer = CreateTimer(GetConVarFloat(g_Reminder)*60, ReminderCallback, _, TIMER_REPEAT);
}

public Action ReminderCallback(Handle hTimer) 
{
	int iMode = GetConVarInt(g_RewardMode);
	if (iMode == 0 || GetArraySize(rewards) == 0) return Plugin_Continue;

	char sMsg[256];
	GetConVarString(g_ReminderMsg, STRING(sMsg));
	ChatAll("%s", sMsg);

	return Plugin_Continue;
}

public void OnLibraryAdded(const char[] name)
{
	if (strcmp(name, "SteamWorks") == 0)
	{
		GetIP();
	}
}

public int SteamWorks_SteamServersConnected()
{
	GetIP();
}

public bool IsLocal(int ip)
{
	if (ip == 0 || 167772160 <= ip <= 184549375 ||
		2886729728 <= ip <= 2887778303 ||
		3232235520 <= ip <= 3232301055)	
		return true;
	return false;
}

public void GetIP()
{	
	if (GetIP_Method1())
		return;

	if (GetIP_Method2())
		return;

	if (GetIP_Method3())
		return;

	if (GetIP_Method4())
		return;
}

public bool GetIP_Method1()
{
	char tmp[64];
	GetConVarString(g_ipOverride, tmp, sizeof(tmp));

	int idx = StrContains(tmp, ":");
	if(idx == -1) 
	{
		Handle serverPort = FindConVar("hostport");
		if (serverPort == INVALID_HANDLE)
			return false;
		g_serverPort = GetConVarInt(serverPort);
	} else 
	{
		tmp[idx] = 0;
		strcopy(g_serverIP, sizeof(g_serverIP), tmp);
		g_serverPort = StringToInt(tmp[idx+1]);
	}

	return strcmp(g_serverIP, "") != 0;
}

public bool GetIP_Method2()
{
	Handle serverIP = FindConVar("hostip");
	Handle serverPort = FindConVar("hostport");
	if (serverIP == INVALID_HANDLE || serverPort == INVALID_HANDLE)
		return false;

	int IP = GetConVarInt(serverIP);
	g_serverPort = GetConVarInt(serverPort);

	Format(g_serverIP, sizeof(g_serverIP), "%d.%d.%d.%d", IP >>> 24 & 255, IP >>> 16 & 255, IP >>> 8 & 255, IP & 255);

	return !IsLocal(IP);
}

public bool GetIP_Method3()
{
	if (!LibraryExists("SteamWorks"))
		return false;

	int IP = SteamWorks_GetPublicIPCell();
	Format(g_serverIP, sizeof(g_serverIP), "%d.%d.%d.%d", IP >>> 24 & 255, IP >>> 16 & 255, IP >>> 8 & 255, IP & 255);

	return IP != 0;
}

public bool GetIP_Method4()
{
	return EasyHTTP("http://ipinfo.io/ip", GET, INVALID_HANDLE, IPReceived, _);
}

public int IPReceived(any data, const char[] buffer, bool success)
{
	if (!success)
	{
		return;
	}

	strcopy(g_serverIP, sizeof(g_serverIP), buffer);
}

public bool OnClientConnect(int client, char[] rejectmsg, int maxlen)
{
	// Set the expected defaults for the client
	VGUICaught[client] = false;
	g_shownTeamVGUI[client] = false;
	g_lastView[client] = 0;
	g_lastReward[client] = 0;
	shouldReward[client] = 0;
	
	if (!StrEqual(gameDir, "left4dead2") && !StrEqual(gameDir, "left4dead") && !StrEqual(gameDir, "csgo"))
		CanReview = true;
	
	return true;
}

public void OnClientPutInServer(int client)
{
	// Load the advertisement via conventional means
	if (StrEqual(gameDir, "left4dead2") && GetConVarBool(g_OnConnect))
	{
		g_playerMidgame[client] = false;
		CreateTimer(0.1, PreMotdTimer, GetClientUserId(client));
	}
}

public void OnMapStart()
{
	Handle DisableMOTD = FindConVar("sv_disable_motd");
	if (DisableMOTD != INVALID_HANDLE)
		SetConVarBool(DisableMOTD, false);
	LoadWhitelist();

	ClearArray(rewards);
	ClearArray(rewardWeights);
}

public Action Command_AddReward(int args)
{
	if (args < 1)
	{
		PrintToServer("Usage: sm_motdgd_add_reward <command> [weight]");
		return Plugin_Handled;
	}

	int weight = 1;
	char command[512];

	if (args > 1)
	{
		GetCmdArg(2, command, sizeof(command));
		weight = StringToInt(command);
	}
	
	PushArrayCell(rewardWeights, weight);
	totalWeight += weight;

	GetCmdArg(1, command, sizeof(command));
	TrimString(command);
	PushArrayString(rewards, command);
	return Plugin_Handled;
}

static const char status[][] =
{
	"socket closed",
	"socket open",
	"upgrading transport",
	"transport upgraded",
	"logged in"
};
	
public Action Command_Hub(int args)
{
	PrintToServer("MOTDgd HUB status: %s", status[hubState]);
	if (hubState == k_LoggedIn)
	{
		PrintToServer("Server ID: %d", ServerID);
	}

	return Plugin_Handled;
}

public Action Command_Ad(int client, int args)
{
	if (client <= 0) return Plugin_Continue;
	
	// Check to make sure the client hasn't blocked html motd. There is no point processing this command for them.
	// But, this response can encourage them to turn html motd on in order to use the reward system.
	QueryClientConVar(client, "cl_disablehtmlmotd", ConVar_DisableHtmlMotd);
			
	shouldReward[client] = GetTime();

	int time1 = !CanReview ? 0 : RoundToCeil((GetConVarFloat(g_Review) * 60 - (GetTime() - g_lastView[client]))/60);
	int time2 = RoundToCeil((GetConVarFloat(g_Cooldown) * 60 - (GetTime() - g_lastReward[client]))/60);

	if (time1 <= 0 && time2 <= 0)
	{
		if (!g_bCSGO)
		{
			if (!g_bClientDisabledMotd[client]) 
			{
				g_lastView[client] = GetTime();
				g_playerMidgame[client] = true;
				CreateTimer(0.1, PreMotdTimer, GetClientUserId(client));
			}
			else
			{
				Chat(client, "You must set 'cl_disablehtmlmotd' to '0' in order to use this command!");
			}
		}
		else
		{
			Chat(client, "To watch an ad, press the SERVER WEBSITE button on the scoreboard.");
		}
	}
	else
	{
		char msg[256];
		char minutes[11];
		GetConVarString(g_CooldownMsg, STRING(msg));
		IntToString(time1 > time2 ? time1 : time2, STRING(minutes));
		ReplaceString(STRING(msg), "{minutes}", minutes);

		Chat(client, "%s", msg);
	}

	return Plugin_Handled;
}

public void ConVar_DisableHtmlMotd(QueryCookie hCookie, int iClient, ConVarQueryResult cvResult, const char[] sCvarName, const char[] sCvarValue)
{
	if (cvResult == ConVarQuery_Okay)
	{
		int iValue = StringToInt(sCvarValue);
		if (iValue == 0)
		{
			g_bClientDisabledMotd[iClient] = false;
		}
		else
		{
			g_bClientDisabledMotd[iClient] = true;
		}
	}
}

// ====[ FUNCTIONS ]=====================================================================

public void LoadWhitelist()
{
	if (g_Whitelist != INVALID_HANDLE) 
	{
		ClearArray(g_Whitelist);
	}
	else
	{
		g_Whitelist = CreateArray(32);
	}

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, STRING(sPath), "configs/motdgd_whitelist.cfg");
	Handle hFile = OpenFile(sPath, "r");
	if (!hFile) 
	{
		return;
	}

	char SteamID[32];
	while(ReadFileLine(hFile, STRING(SteamID)))
	{
		PushArrayString(g_Whitelist, SteamID[8]);
	}

	CloseHandle(hFile);
}

public Action Event_End(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	// Re-view minutes must be 15 or higher, re-view mode (onother) for this event
	if (GetConVarFloat(g_Review) < 10.0 || (g_OnOther && GetConVarInt(g_OnOther) != 1 && GetConVarInt(g_OnOther) != 3 && GetConVarInt(g_OnOther) != 5 && GetConVarInt(g_OnOther) != 7))
		return Plugin_Continue;
	
	// Only process the re-view event if the client is valid and is eligible to view another advertisement
	if (IsValidClient(client) && CanReview && GetTime() - g_lastView[client] >= GetConVarFloat(g_Review) * 60)
	{
		g_lastView[client] = GetTime();
		g_playerMidgame[client]=true;
		CreateTimer(0.1, PreMotdTimer, GetClientUserId(client));
	}

	return Plugin_Continue;
}

public Action Event_Death(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (!client)
		return Plugin_Continue;

	CreateTimer(0.5, CheckPlayerDeath, GetClientUserId(client));
	
	return Plugin_Continue;
}

public Action Event_Start(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	// Re-view minutes must be 15 or higher, re-view mode (onother) for this event
	if (GetConVarFloat(g_Review) < 10.0 || (g_OnOther && GetConVarInt(g_OnOther) != 4 && GetConVarInt(g_OnOther) != 5 && GetConVarInt(g_OnOther) != 6 && GetConVarInt(g_OnOther) != 7))
		return Plugin_Continue;
	
	// Only process the re-view event if the client is valid and is eligible to view another advertisement
	if (IsValidClient(client) && CanReview && GetTime() - g_lastView[client] >= GetConVarFloat(g_Review) * 60)
	{
		g_lastView[client] = GetTime();
		g_playerMidgame[client]=true;
		CreateTimer(0.1, PreMotdTimer, GetClientUserId(client));
	}

	return Plugin_Continue;
}

public Action CheckPlayerDeath(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);
	if (!client)
		return Plugin_Stop;

	// Check if client is valid
	if (!IsValidClient(client))
		return Plugin_Stop;
	
	// We don't want TF2's Dead Ringer triggering a false re-view event
	if (IsPlayerAlive(client))
		return Plugin_Stop;
	
	// Re-view minutes must be 15 or higher, re-view mode (onother) for this event
	if (GetConVarFloat(g_Review) < 10.0 || (g_OnOther && GetConVarInt(g_OnOther) != 2 && GetConVarInt(g_OnOther) != 3 && GetConVarInt(g_OnOther) != 6 && GetConVarInt(g_OnOther) != 7))
		return Plugin_Stop;
	
	// Only process the re-view event if the client is valid and is eligible to view another advertisement
	if (CanReview && GetTime() - g_lastView[client] >= GetConVarFloat(g_Review) * 60)
	{
		g_lastView[client] = GetTime();
		g_playerMidgame[client]=true;
		CreateTimer(0.1, PreMotdTimer, GetClientUserId(client));
	}
	
	return Plugin_Stop;
}

public Action Event_PlayerTransitioned(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (IsValidClient(client) && GetConVarBool(g_OnConnect))
	{
		g_playerMidgame[client]=true;
		CreateTimer(0.1, PreMotdTimer, GetClientUserId(client));
	}

	return Plugin_Continue;
}

public Action OnVGUIMenu(UserMsg msg_id, Handle bf, const int[] players, int playersNum, bool reliable, bool init)
{
	if (!(playersNum > 0))
		return Plugin_Handled;
	int client = players[0];
		
	if (playersNum > 1 || !IsValidClient(client) || VGUICaught[client] || !GetConVarBool(g_OnConnect))
		return Plugin_Continue;

	VGUICaught[client] = true;
	g_lastView[client] = GetTime();
	g_playerMidgame[client] = false;
	CreateTimer(0.1, PreMotdTimer, GetClientUserId(client));
	return Plugin_Handled;
}

public Action ClosedMOTD(int client, const char[] command, int argc)
{
	if (!IsValidClient(client))
		return Plugin_Handled;
	
	if (g_forced != INVALID_HANDLE && GetConVarInt(g_forced) != 0 && g_lastView[client] != 0 && (g_lastView[client]+GetConVarInt(g_forced) >= GetTime()))
	{
		int timeRemaining = ((g_lastView[client]+GetConVarInt(g_forced)) - GetTime()) + 1;
		
		if (timeRemaining == 1)
		{
			PrintCenterText(client, "Please wait %i second", timeRemaining);
		}
		else
		{
			PrintCenterText(client, "Please wait %i seconds", timeRemaining);
		}
		
		if (StrEqual(gameDir, "cstrike"))
			ShowMOTDScreen(client, "", false);
		else
			ShowMOTDScreen(client, "http://", false);
	}
	else
	{
        if (StrEqual(gameDir, "cstrike") || StrEqual(gameDir, "csgo") || StrEqual(gameDir, "csco") || StrEqual(gameDir, "insurgency") || StrEqual(gameDir, "brainbread2") || StrEqual(gameDir, "nmrih"))
            FakeClientCommand(client, "joingame");
        else if (StrEqual(gameDir, "nucleardawn") || StrEqual(gameDir, "dod"))
            ClientCommand(client, "changeteam");
	}
	
	return Plugin_Handled;
}

public Action PreMotdTimer(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);
	if (!client)
		return Plugin_Stop;

	if (!IsValidClient(client))
		return Plugin_Stop;
		
	// Don't bother with clients that have disabled html motd.
	if (!g_bCSGO) QueryClientConVar(client, "cl_disablehtmlmotd", ConVar_DisableHtmlMotd);
	if (g_bClientDisabledMotd[client])
		return Plugin_Stop;
	
	char url[255];
	char steamid[255]="NULL";
	char name[MAX_NAME_LENGTH];
	char name_encoded[MAX_NAME_LENGTH*2];
	GetClientName(client, name, sizeof(name));
	urlencode(name, name_encoded, sizeof(name_encoded));

	GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
	Format(url, sizeof(url), "http://motd.motdgd.com/?user=%d&ip=%s&pt=%d&v=%s&st=%s&gm=%s&name=%s&srv_id=%d&clt_user=%s", GetConVarInt(g_motdID), g_serverIP, g_serverPort, PLUGIN_VERSION, steamid, gameDir, name_encoded, ServerID, steamid);
	
	if (g_playerMidgame[client])
	{
		Format(url, sizeof(url), "%s&midgame=1&audio=%d", url, GetConVarInt(g_audioOnly));
	}

	if (FindStringInArray(g_Whitelist, steamid[8]) != -1)
	{
		return Plugin_Stop;
	}

	if (g_forced != INVALID_HANDLE && GetConVarInt(g_forced) != 0)
	{
		CreateTimer(0.2, RefreshMotdTimer, userid);
	}

	if (g_autoClose != INVALID_HANDLE)
	{
		float close = GetConVarFloat(g_autoClose);
		if (close > 0)
		{
			CreateTimer(close, AutoCloseTimer, userid);
		}
	}

	// Hopefully temporary TF2 workaround
	if (StrEqual(gameDir, "tf"))
	{
		char refreshUrl[255];
		Format(refreshUrl, sizeof(refreshUrl), "http://hub.motdgd.com/refresh?user=%d&ip=%s&pt=%d&v=%s&st=%s&gm=%s&name=%s", GetConVarInt(g_motdID), g_serverIP, g_serverPort, PLUGIN_VERSION, steamid, gameDir, name_encoded);
		EasyHTTP(refreshUrl, GET, INVALID_HANDLE, RefreshReceived, _);
	}

	ShowMOTDScreen(client, url, false); // False means show, true means hide
	
	return Plugin_Stop;
}

public int RefreshReceived(any data, const char[] buffer, bool success)
{

}

public Action AutoCloseTimer(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);
	
	if (!client)
		return Plugin_Stop;

	ShowMOTDScreen(client, "http://", true);
	ClosedMOTD(client, "", 0);

	return Plugin_Stop;
}

public Action RefreshMotdTimer(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);
	
	if (!client)
		return Plugin_Stop;

	if (!IsValidClient(client))
		return Plugin_Stop;

	if (g_forced != INVALID_HANDLE && GetConVarInt(g_forced) != 0 && g_lastView[client] != 0 && (g_lastView[client]+GetConVarInt(g_forced)) >= GetTime())
	{
		CreateTimer(0.3, RefreshMotdTimer, userid);
	}

	ShowMOTDScreen(client, "http://", false);

	return Plugin_Stop;
}

stock void ShowMOTDScreen(int client, char[] url, bool hidden)
{
	if (!IsValidClient(client))
		return;
	
	Handle kv = CreateKeyValues("data");

	if (StrEqual(gameDir, "left4dead") || StrEqual(gameDir, "left4dead2"))
		KvSetString(kv, "cmd", "closed_htmlpage");
	else
		KvSetNum(kv, "cmd", 5);

	if (StrEqual(gameDir, "tf") && g_playerMidgame[client])
	{
		//KvSetNum(kv, "customsvr", 1);
	}

	KvSetString(kv, "msg", url);
	KvSetString(kv, "title", "MOTDgd AD");
	KvSetNum(kv, "type", MOTDPANEL_TYPE_URL);
	ShowVGUIPanel(client, "info", kv, !hidden);
	CloseHandle(kv);
}

stock int GetRealPlayerCount()
{
	int players;
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
			players++;
	}
	return players;
}

stock bool IsValidClient(int i)
{
	if (!i || !IsClientInGame(i) || IsClientSourceTV(i) || IsClientReplay(i) || IsFakeClient(i) || !IsClientConnected(i))
		return false;
	if (!GetConVarBool(g_immunity))
		return true;
	if (CheckCommandAccess(i, "MOTDGD_Immunity", ADMFLAG_RESERVATION))
		return false;

	return true;
}

stock void urlencode(const char[] sString, char[] sResult, int len)
{
	char sHexTable[] = "0123456789abcdef";
	int from, c;
	int to;

	while (from < len)
	{
		c = sString[from++];
		if (c == 0)
		{
			sResult[to++] = c;
			break;
		}
		else if (c == ' ')
		{
			sResult[to++] = '+';
		}
		else if ((c < '0' && c != '-' && c != '.') ||
				(c < 'A' && c > '9') ||
				(c > 'Z' && c < 'a' && c != '_') ||
				(c > 'z'))
		{
			if ((to + 3) > len)
			{
				sResult[to] = 0;
				break;
			}
			sResult[to++] = '%';
			sResult[to++] = sHexTable[c >> 4];
			sResult[to++] = sHexTable[c & 15];
		}
		else
		{
			sResult[to++] = c;
		}
	}
}  

// Socket.io

char yeast_alphabet[] = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_";
const int yeast_length = 64;
int yeast_seed = 0;
char yeast_prev[256];

public void yeast_encode(int num, char[] out, int maxlen)
{

	int i = num <= 0 ? 0 : RoundToFloor(Logarithm(float(num), float(yeast_length)));
	do
	{
		out[i--] = yeast_alphabet[num % yeast_length];
		num = num / yeast_length;
	}
	while (num > 0);
}

public void yeast(char[] out, int maxlen)
{
	char now[128];
	char seedpp[128];

	yeast_encode(GetTime(), now, sizeof(now));

	if (strcmp(now, yeast_prev) != 0)
	{
		yeast_seed = 0;
		strcopy(yeast_prev, sizeof(yeast_prev), now);
		strcopy(out, maxlen, now);
		return;
	}
	
	yeast_encode(yeast_seed++, seedpp, sizeof(seedpp));
	Format(out, maxlen, "%s.%s", now, seedpp);
}

Action connectHub(Handle hTimer = INVALID_HANDLE)
{
	hub = SocketCreate(SOCKET_TCP, OnSocketError);
	SocketConnect(hub, OnSocketConnected, OnSocketReceive, OnSocketDisconnected, "hub.motdgd.com", 80);
}

public void OnSocketConnected(Handle socket, any arg)
{
	hubState = k_Connected;

	// socket is connected, send the http request
	LogMessage("## Socket connected");
	char requestStr[512];
    
	char cb[128];
	yeast(cb, sizeof(cb));
	Format(requestStr, sizeof(requestStr), "GET /%s%s HTTP/1.1\r\nHost: %s\r\n\r\n", "socket.io/?EIO=3&transport=polling&t=", cb, "hub.motdgd.com");
	SocketSend(socket, requestStr);
}

public void OnSocketError(Handle s, int errorType, int errorNum, any arg)
{
	LogMessage("## Socket error: %d %d", errorType, errorNum);
}

public void OnSocketDisconnected(Handle s, any data)
{
	LogMessage("## Socket disconnected.");
	hub = INVALID_HANDLE;
	hubState = k_Closed;
	if (pingTimer != INVALID_HANDLE)
	{
		KillTimer(pingTimer);
		pingTimer = INVALID_HANDLE;
	}

	if (timeoutTimer != INVALID_HANDLE)
	{
		KillTimer(timeoutTimer);
		timeoutTimer = INVALID_HANDLE;
	}

	CreateTimer(reconnectDelay, connectHub);
	reconnectDelay = reconnectDelay > 55.0 ? 60.0 : reconnectDelay + 5.0;
}

public void OnSocketReceive(Handle socket, char[] receiveData, const int dataSize, any hFile)
{
	if (hubState == k_Connected && StrContains(receiveData, "HTTP/1.1 200 OK", true) != -1)
	{
		int body = StrContains(receiveData, "\r\n\r\n")+4;
		int packet_length = StringToInt(receiveData[body]);

		char msg[128];
		strcopy(msg, sizeof(msg) > packet_length+1 ? packet_length+1 : sizeof(msg), receiveData[body+StrContains(receiveData[body], ":")+1]);

		handleEngineIO(socket, msg);
	}
	else if (hubState == k_Connected && StrContains(receiveData, "HTTP/1.1 101 Switching Protocols", true) == 0)
	{
		LogMessage("## Started switching protocols");
		hubState = k_Upgrading;
		sendRawMessage(socket, "2probe");

	}
	else if (hubState >= k_Upgrading)
	{
		handleWebsocket(socket, receiveData);
	}
	else if (hubState < k_Upgrading)
	{
		LogMessage("## Couldn't connect to HUB, retrying...");
		CloseHandle(hub);
		hub = INVALID_HANDLE;
		OnSocketDisconnected(hub, false);
	}
}

public void handleWebsocket(Handle socket, char[] msg)
{
	//int FIN = (msg[0] & 0b10000000) >> 7;
	int OP = (msg[0] & 0b00001111) >> 0;
	//int MASK = (msg[1] & 0b10000000) >> 7;
	int LEN = (msg[1] & 0b01111111) >> 0;
	int PAYLOAD = 2;
	if (LEN < 126)
	{
		//LogMessage("## FIN=%u OP=%u MASK=%u LEN=%u PAYLOAD=%s", FIN, OP, MASK, LEN, msg[PAYLOAD]);
		switch(OP)
		{
			case 1:
			{
				handleEngineIO(socket, msg[PAYLOAD]);
			}

			case 8:
			{
				LogMessage("## Remote HUB closed connection");
				CloseHandle(hub);
				hub = INVALID_HANDLE;
				OnSocketDisconnected(hub, false);
			}

			case 9:
			{
				LogMessage("## Websocket ping received");
				sendRawMessage(socket, "", 10);
			}

			default:
			{
				LogMessage("## Unknown websocket operation %d", OP);
			}
		}
	}
	else
	{
		LogMessage("## Unsupported message length");
	}
}

public void handleEngineIO(Handle socket, char[] msg)
{
	char packet[512];
	Handle json = INVALID_HANDLE;

	switch(msg[0])
	{
		// open
		case '0':
		{
			// Get SID
			json = DecodeJSON(msg[1]);

			JSONGetString(json, "sid", sid, sizeof(sid));
			JSONGetInteger(json, "pingInterval", pingInterval);
			JSONGetInteger(json, "pingTimeout", pingTimeout);
			DestroyJSON(json);

			LogMessage("## Connection SID: %s", sid);
			LogMessage("## Ping interval: %d", pingInterval);
			LogMessage("## Ping timeout: %d", pingTimeout);

			if (pingTimer != INVALID_HANDLE)
			{
				KillTimer(pingTimer);
				pingTimer = INVALID_HANDLE;
			}
			pingTimer = CreateTimer(pingInterval/1000.0, PingTimerCallback, _, TIMER_REPEAT);

			// Upgrade connection
			Format(packet, sizeof(packet), "GET /%s%s HTTP/1.1\r\nHost: %s\r\nConnection: Upgrade\r\nUpgrade: WebSocket\r\nOrigin: http://hub.motdgd.com/\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: %s\r\n\r\n", "socket.io/?EIO=3&transport=websocket&sid=", sid, "hub.motdgd.com:", "YW4gc3JjZHMgd3MgdGVzdA==");
			SocketSend(socket, packet);
		}

		// ping
		case '2':
		{
			if (strcmp(msg[1], "probe") == 0)
			{
				sendRawMessage(socket, "3probe");
			}
			else
			{
				LogMessage("Unexpected message %s", msg[1]);
			}
		}

		// pong
		case '3':
		{
			if (strcmp(msg[1], "probe") == 0)
			{
				if (hubState == k_Upgrading)
				{

					// Finish switching protocol
					sendRawMessage(socket, "5");
					hubState = k_Upgraded;

					// Log in to HUB
					Format(packet, sizeof(packet), "42[\"login\", %d, \"%s\", \%d, \"\", \"motdgd\", \"%s\", \"%s\", %d]", GetConVarInt(g_motdID), g_serverIP, g_serverPort, PLUGIN_VERSION, gameDir, ServerID);
					sendRawMessage(socket, packet);
				}
			}
			else if (hubState == k_LoggedIn)
			{

				//LogMessage("## Heartbeat received");
				if (timeoutTimer != INVALID_HANDLE)
				{
					KillTimer(timeoutTimer);
					timeoutTimer = INVALID_HANDLE;
				}
			}
			else
			{
				LogMessage("Unexpected message %s", msg[1]);
			}
		}

		// message
		case '4':
		{
			handleSocketIO(socket, msg[1]);
		}

		default:
		{
			LogMessage("Unexpected engine.io operation %d", msg[0]);
		}
	}
}

public void handleSocketIO(Handle socket, char[] msg)
{
	int client = -1;
	char event[32];
	char player[64];
	Handle json = INVALID_HANDLE;

	switch(msg[0])
	{
		// event
		case '2':
		{
			json = DecodeArray(msg[1]);
			JSONGetArrayString(json, 0, event, sizeof(event));
			if (GetArraySize(json) > 1)
			{
				if (strcmp(event, "login_response") == 0)
				{
					JSONGetArrayInteger(json, 1, ServerID);
					hubState = k_LoggedIn;
					reconnectDelay = 0.1;

					char motdfile[64];
					char url[256];
					Format(STRING(url), "http://motd.motdgd.com/?user=%d&ip=%s&pt=%d&v=%s&gm=%s&srv_id=%d", GetConVarInt(g_motdID), g_serverIP, g_serverPort, PLUGIN_VERSION, gameDir, ServerID);

					GetConVarString(FindConVar("motdfile"), STRING(motdfile));
					Handle motdtxt = OpenFile(motdfile, "w+");
					WriteFileString(motdtxt, url, false);
					CloseHandle(motdtxt);

					if (GetConVarInt(g_serverID) == -1)
					{
						SetConVarInt(g_serverID, ServerID);

						char currentMap[PLATFORM_MAX_PATH];
						GetCurrentMap(currentMap, sizeof(currentMap));
						ForceChangeLevel(currentMap, "Restarting map one-time in order to ensure that the MOTDgd Server ID is in sync with the new MOTD URL");

						return;
					}

					LogMessage("## Connected to the HUB with ID %d", ServerID);
				}
				else if (strcmp(event, "aderror_response") == 0)
				{
					JSONGetArrayString(json, 1, player, sizeof(player));
					//LogMessage("## No ad found for %s", player);

					client = GetClientByIP(player);
					if (client <= 0) client = GetClientBySteamID(player);
					if (client > 0)
					{
						if (GetConVarInt(g_RewardNoAd) == 1)
						{
							RewardPlayer(client);
						}
						else
						{
							NoRewardPlayer(client);
						}
					}
				}
				else if (strcmp(event, "complete_response") == 0)
				{
					JSONGetArrayString(json, 1, player, sizeof(player));
					//LogMessage("## Ad finished for %s", player);

					client = GetClientByIP(player);
					if(client <= 0) client = GetClientBySteamID(player);
					if(client > 0)
					{
						RewardPlayer(client);
					}
				}
				else
				{
					LogMessage("Unexpected HUB event %s", event);
				}
			}
			else
			{
				LogMessage("Empty HUB event %s", event);
			}

			DestroyJSONArray(json);
		}

		default:
		{
			LogMessage("Unexpected socket.io operation %d", msg[0]);
		}
	}
}

void sendRawMessage(Handle socket, char[] message, int op = 1)
{
	char packet[256];
	int size = 0;
	if (strlen(message) < 126)
	{
		packet[0] = 1 << 7; // FIN=1
		packet[0] += op << 0; // OP=0x1
		packet[1] = 1 << 7; // MASK=1
		packet[1] += strlen(message); //LEN=strlen(message)
		packet[2] = GetRandomInt(0, 255);
		packet[3] = GetRandomInt(0, 255);
		packet[4] = GetRandomInt(0, 255);
		packet[5] = GetRandomInt(0, 255);
		for(int i = 0; i < strlen(message); ++i)
		{
			packet[6+i] = message[i] ^ packet[2+(i%4)];
		}
		size = 6 + strlen(message);
		//LogMessage("### %x - %u", packet[2], packet[6]);
	}
	else
	{
		LogMessage("## Unsupported message length");
		return;
	}
	SocketSend(socket, packet, size);
}

public Action PingTimerCallback(Handle timer)
{
	if (hubState == k_Closed)
	{
		pingTimer = INVALID_HANDLE;
		return Plugin_Stop;
	}

	//LogMessage("## Sending heartbeat");
	sendRawMessage(hub, "2");
	if (timeoutTimer == INVALID_HANDLE)
	{
		timeoutTimer = CreateTimer(pingTimeout/1000.0, PingTimedout);
	}

	return Plugin_Continue;
}

public Action PingTimedout(Handle timer)
{
	LogMessage("## Remote HUB timed out");
	CloseHandle(hub);
	hub = INVALID_HANDLE;
	timeoutTimer = INVALID_HANDLE;
	OnSocketDisconnected(hub, false);
	return Plugin_Stop;
}

public void RewardPlayer(int client)
{
	int mode = GetConVarInt(g_RewardMode);
	if (mode == 0 || GetArraySize(rewards) == 0) return;

	if (GetConVarInt(g_RewardEvents) != 1 && strcmp(gameDir, "csgo") != 0 && shouldReward[client]+90 < GetTime())
	{
		return;
	}

	char msg[256];
	if (GetRandomFloat() >= GetConVarFloat(g_RewardChance))
	{
		GetConVarString(g_NoRewardMsg, STRING(msg));
		Chat(client, "%s", msg);
		return;
	}

	int time = RoundToCeil((GetConVarFloat(g_Cooldown) * 60 - (GetTime() - g_lastReward[client]))/60);
	if (time > 0)
	{
		char minutes[11];
		GetConVarString(g_CooldownMsg, STRING(msg));
		IntToString(time, STRING(minutes));
		ReplaceString(STRING(msg), "{minutes}", minutes);

		Chat(client, "%s", msg);
		return;
	}

	g_lastReward[client] = GetTime();

	if (mode == 1)
	{
		for (int i = 0; i < GetArraySize(rewards); ++i)
		{
			GiveReward(client, i);
		}
	}
	else if (mode == 2)
	{
		GiveReward(client, GetRandomInt(0, GetArraySize(rewards)-1));
	}
	else if (mode == 3)
	{
		int rand = GetRandomInt(1, totalWeight);
		int sum = 0;
		for (int i = 0; i < GetArraySize(rewards); ++i)
		{
			sum += GetArrayCell(rewardWeights, i);
			if (rand <= sum)
			{
				GiveReward(client, i);
				break;
			}
		}
	}

	char message[256];
	GetConVarString(g_RewardMsg, STRING(message));
	ReplacePlaceholders(client, STRING(message));
	Chat(client, "%s", message);
}

public void NoRewardPlayer(int client)
{
	int mode = GetConVarInt(g_RewardMode);
	if (mode == 0 || GetArraySize(rewards) == 0) return;

	if (strcmp(gameDir, "csgo") != 0 && shouldReward[client]+120 < GetTime())
	{
		return;
	}

	char message[256];
	GetConVarString(g_NoVideoMsg, STRING(message));
	ReplacePlaceholders(client, STRING(message));
	Chat(client, "%s", message);
}

public void GiveReward(int client, int idx)
{
	char command[512];
	GetArrayString(rewards, idx, STRING(command));
	
	int sep = StrContains(command, " ");
	if (sep > 0)
	{
		command[sep] = 0;
	}

	Handle data;
	if (GetTrieValue(handlers, command, data) == true)
	{
		char split[16][64];
		int strings = ExplodeString(command[sep+1], " ", split, sizeof(split[]), sizeof(split[][]));

		Call_StartFunction(ReadPackCell(data), ReadPackFunction(data));
		Call_PushCell(client);
		ResetPack(data);

		for (int i = 0; i < strings; ++i)
		{
			Call_PushString(split[i]);
		}

		Call_Finish();
	}
	else
	{
		command[sep] = ' ';
		ReplacePlaceholders(client, STRING(command));
		InsertServerCommand("%s", command);
	}
}

public void ReplacePlaceholders(int client, char[] msg, int maxlen)
{
	char name[64];
	char steamid[64];
	char communityid[64];
	char userid[11];
	char clientid[11];
	Format(STRING(name), "\"%N\"", client);
	GetClientAuthId(client, AuthId_Steam2, steamid[1], sizeof(steamid)-2);
	steamid[0]='"';
	steamid[strlen(steamid)]='"';
	GetClientAuthId(client, AuthId_SteamID64, STRING(steamid));
	IntToString(client, STRING(clientid));
	IntToString(GetClientUserId(client), STRING(userid));
	ReplaceString(msg, maxlen, "{name}", name);
	ReplaceString(msg, maxlen, "{steamid}", steamid);
	ReplaceString(msg, maxlen, "{steamid64}", communityid);
	ReplaceString(msg, maxlen, "{userid}", userid);
	ReplaceString(msg, maxlen, "{client}", clientid);
}

public int Native_AddRewardHandler(Handle plugin, int numParams)
{
	char id[32];
	GetNativeString(1, id, sizeof(id));
	Function cb = GetNativeFunction(2);
	Handle data = CreateDataPack();
	WritePackCell(data, plugin);
	WritePackFunction(data, cb);
	ResetPack(data);
	SetTrieValue(handlers, id, data);
	return true;
}

public int Native_RemoveRewardHandler(Handle plugin, int numParams)
{
	char id[32];
	GetNativeString(1, id, sizeof(id));
	Handle data;
	GetTrieValue(handlers, id, data);
	CloseHandle(data);
	RemoveFromTrie(handlers, id);
	return true;
}