/*
 * Helper container for splits
 */
class Split{
	vec4 color;
	string diff;
	int64 diff_num;
}


enum ColorPolicy {
	relative = 1,
	absolute = 2
}

enum DisplayStyle {
	stacking = 3,
	table = 4
}

// CONSTANTS
const int64 invalidDiff = -9223372036854775808;
const vec4 colorBlue = vec4(0, 0, 0.8, 0.8);
const vec4 colorRed = vec4(0.8, 0, 0, 0.8);
const vec4 colorGrey = vec4(0.6, 0.6, 0.6, 0.8);
const vec4 colorGreyBg = vec4(0.5, 0.5, 0.5, 0.7);
const vec4 colorNormal = vec4(1, 1, 1, 1);

// SETTINGS

[Setting name="Font size" min=8 max=64]
uint fontSize = 32;

[Setting name="Split History size" min=1 max=128]
uint maxHistory = 32;

[Setting name="Splits coloring" description="absolute - like in TM, relative - correct one"]
ColorPolicy colorPolicy = relative;

[Setting name="Display style" description="stacking may obfuscate screen a bit less, table will also add as CP counter"]
DisplayStyle displayStyle = table;

[Setting name="Position X" min=0.0 max=1.0]
float anchorX = 1.0;
[Setting name="Position Y" min=0.0 max=1.0]
float anchorY = .1;

[Setting name="Show Only after finish"]
bool showAfterFinish=false;

// GLOBALS
int64 lastCPDiff = 0;
int startIdx = -1;
int preCPIdx = -1;
array<Split> splits = {};
uint totalCPs = 0; 



// DRAWING PARAMS
float margin_y = fontSize * 0.1;
float margin_x = fontSize * 0.5;
float text_w = 0.0;
float text_x = 0.0;
float text_y = 0.0;
float box_x = 0.0;
float box_y = 0.0;
float box_w = 0.0;
float box_h = 0.0;


void Render() 
{
	if (showAfterFinish && splits.Length != totalCPs) {
		return;
	}
	float offset_y = 0.0;

	nvg::FontSize(fontSize);
	switch(displayStyle){
		case table:
			// fillers if enabled
			if (totalCPs != splits.Length) {
			nvg::BeginPath();
			nvg::Rect(box_x, box_y, box_w, box_h*(totalCPs - splits.Length));
			nvg::FillColor(colorGreyBg);
			nvg::Fill();
			nvg::ClosePath();
			}
			offset_y = box_h*(totalCPs - splits.Length);
			// ayyy finally used fallthrougn switch :)
		case stacking:
			for(int i = splits.Length-1; i >= 0; i--)
			{
				// box color decoration
				nvg::BeginPath();
				nvg::Rect(box_x, box_y + offset_y, box_w, box_h);
				nvg::FillColor(splits[i].color);
				nvg::Fill();
				nvg::ClosePath();
				// text
				nvg::FillColor(colorNormal);
				nvg::TextAlign(nvg::Align::Right | nvg::Align::Top);
				nvg::TextBox(text_x, text_y + offset_y, text_w, splits[i].diff);
				offset_y += box_h;
			}
			break;
	}
}


void Update(float dt) 
{
	auto playground = cast<CSmArenaClient>(GetApp().CurrentPlayground);

	if (playground is null
		|| playground.Arena is null
		|| playground.Map is null
		|| playground.GameTerminals.Length <= 0
		|| (playground.GameTerminals[0].UISequence_Current != CGamePlaygroundUIConfig::EUISequence::Playing
			&& playground.GameTerminals[0].UISequence_Current != CGamePlaygroundUIConfig::EUISequence::Finish
			&& playground.GameTerminals[0].UISequence_Current != CGamePlaygroundUIConfig::EUISequence::EndRound) )
	{
		// menu
		lastCPDiff = 0;
		splits = {};
		totalCPs = 0;
		return;
	}
	
	auto player = cast<CSmPlayer>(playground.GameTerminals[0].GUIPlayer);
	auto scriptPlayer = player is null ? null : cast<CSmScriptPlayer>(player.ScriptAPI);
	

	if (playground.GameTerminals[0].UISequence_Current != CGamePlaygroundUIConfig::EUISequence::EndRound)
	{ 
		// screen after finish?
		if (scriptPlayer is null || player.CurrentLaunchedRespawnLandmarkIndex == uint(-1)) 
		{
			lastCPDiff = 0;
			preCPIdx = -1;
			startIdx = -1;
			splits = {};
			totalCPs = 0;
			return;
		}
	}

	
	if (playground.GameTerminals[0].UISequence_Current == CGamePlaygroundUIConfig::EUISequence::Playing)
	{
		// start
		if (preCPIdx == -1)
		{
			preCPIdx = player.CurrentLaunchedRespawnLandmarkIndex;
			startIdx = preCPIdx;
			lastCPDiff = 0;
			splits = {};
			totalCPs =  getTotalCPs(playground);
			setDrawingCoordinates();
		}
		// next cp and sometimes finish apparently
		else
		{
			if (preCPIdx != int(player.CurrentLaunchedRespawnLandmarkIndex))
			{
				preCPIdx = player.CurrentLaunchedRespawnLandmarkIndex;
				if (preCPIdx == startIdx) {
					preCPIdx = -1;
					return;
				}
				int64 diff = GetDiffPB();
				if (diff !=invalidDiff)
				{
					newCP(diff);
				}
			}
		}
	}

    // finish always
	else if (preCPIdx != -1)
	{
		preCPIdx = -1;
		int64 diff = GetDiffPB();
		if (diff !=invalidDiff && splits.Length < totalCPs)
		{
			newCP(diff);
		}
	}
}


vec4 colorAbsolute(int64 diff) {
	if (diff > 0) {
		return colorRed;
	} else if (diff < 0) {
		return colorBlue;
	} else {
		return colorGrey;
	}
}

vec4 colorRelative(int64 diff) {
	if (diff - lastCPDiff > 0) {
		return colorRed;
	} else if (diff - lastCPDiff < 0) {
		return colorBlue;
	} else {
		return colorGrey;
	}
}

void newCP(int64 diff)
{
	Split newSplit;
	switch (colorPolicy) {
		case relative:
			newSplit.color = colorRelative(diff);
			break;
		case absolute:
			newSplit.color = colorAbsolute(diff);
			break;
	}
	newSplit.diff = FormatDiff(diff);
	newSplit.diff_num = diff;
	if (splits.Length >= maxHistory)
	{
		splits.RemoveAt(0);
	}
	splits.InsertLast(newSplit);
	setDrawingCoordinates();
	lastCPDiff = diff;
}

void setDrawingCoordinates()
{
	const uint text_length = 10;
	text_w = text_length * fontSize * 0.52;
	box_w = text_w + 2*margin_x;

	float adjusted_anchorX = anchorX*Draw::GetWidth();
	float adjusted_anchorY = anchorY*Draw::GetHeight();
	if(adjusted_anchorX < box_w*0.5)
	{
		adjusted_anchorX =  box_w*0.5;
	} 
	else if(adjusted_anchorX > Draw::GetWidth()-box_w*0.5)
	{
		adjusted_anchorX =  Draw::GetWidth()-box_w*0.5;
	}

	text_x = adjusted_anchorX - 0.5*text_w;
	text_y = adjusted_anchorY + margin_y;
	box_x = text_x - margin_x;
	box_y = text_y-margin_y;
	box_h = fontSize + 2*margin_y;
}

// Yoinked from NoRespawnTimer by ~AnfR82
string FormatDiff(int64 time)
{
	string str = "+";
	if (time < 0)
	{
		str = "-";
		time *= -1;
	}
	double tm = time / 1000.0;

	int hundredth = int((tm % 1.0) * 1000);
	int seconds = int(tm % 60);
	int minutes = int(tm / 60) % 60;
	int hours = int(tm / 60 / 60);

	if (hours > 0) str += hours + ":";
	str += formatInt(minutes) + ":";
	str += formatInt(seconds) + ".";
	str += formatInt(hundredth,3);

	return str;
}

string formatInt(int number, int target = 2)
{
	string ret = ""+number;
	while(ret.Length < target){
		ret = "0"+ ret;
	}
	return ret;
}

// Yoinked from NoRespawnTimer by ~AnfR82
int64 GetDiffPB()
{
	auto network = GetApp().Network;
	
	if (network.ClientManiaAppPlayground !is null && 
		network.ClientManiaAppPlayground.UILayers.Length > 0) 
	{
		auto uilayers = network.ClientManiaAppPlayground.UILayers;

		for (uint i = 0; i < uilayers.Length; i++)
		{
			CGameUILayer@ curLayer = uilayers[i];
			int start = curLayer.ManialinkPageUtf8.IndexOf("<");
			int end = curLayer.ManialinkPageUtf8.IndexOf(">");
			if (start != -1 && end != -1) 
			{
				auto manialinkname = curLayer.ManialinkPageUtf8.SubStr(start, end);
				if (manialinkname.Contains("UIModule_Race_Checkpoint")) 
				{
					auto c = cast<CGameManialinkLabel@>(curLayer.LocalPage.GetFirstChild("label-race-diff"));
					if (c.Visible && c.Parent.Visible) // reference lap not finished 
					{
						string diff = c.Value;
						int64 res = 0;
						if (diff.Length == 10) // invalid format
						{
							res = diff.SubStr(0,1) == "-" ? -1 : 1;
							int min = Text::ParseInt(diff.SubStr(1, 2));
							int sec = Text::ParseInt(diff.SubStr(4, 2));
							int ms = Text::ParseInt(diff.SubStr(7, 3));
							res *= (min * 60000) + (sec * 1000) + ms;
						}
						return res;
					}
				}
			}
		}		
	}
	return invalidDiff;
}

// Yoinked and repurposed from CheckpointCounter by ~Phlarx
uint getTotalCPs(CSmArenaClient& playground){
	int _maxCP = 0;
	int _maxLap = 1;
	// TMObjective_NbLaps is set to some weird value when no laps
	if (playground.Map.TMObjective_IsLapRace) {
		_maxLap = playground.Map.TMObjective_NbLaps;
	}
	array<int> links = {};
	MwFastBuffer<CGameScriptMapLandmark@> landmarks = playground.Arena.MapLandmarks;
	for(uint i = 0; i < landmarks.Length; i++) {
		if(landmarks[i].Waypoint !is null && !landmarks[i].Waypoint.IsFinish && !landmarks[i].Waypoint.IsMultiLap) {
			if(landmarks[i].Tag == "Checkpoint") {
				_maxCP += 1;
			} else if(landmarks[i].Tag == "LinkedCheckpoint") {
				if(links.Find(landmarks[i].Order) < 0) {
					_maxCP += 1;
					links.InsertLast(landmarks[i].Order);
				}
			} else {
				_maxCP += 1;
			}
		}
	}

	return _maxCP*_maxLap + 1; // + finish

}

void OnSettingsChanged() {
	// Settings change feedback
	if (splits.Length > 0) {
		setDrawingCoordinates();
	}
}

// TODO
// Speeeeeed? hard + you need storage
// maybe some nice graph at the end
