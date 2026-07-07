//==================================================================================
// Today's the Day
// ©2023 Steve Crutchfield
// -----------------------
// 
// Patches DrawString in the Finder to draw "Today" or "Yesterday" (localizable in
// STR resources #128 and 129) when it's drawing a string that begins with the 
// relevant date.  Works in both folder list views and Get Info windows.
//
// Also patches DrawText because System 6 uses that for Get Info windows.
//
// Patches ONLY the Finder by first patching SystemEvent and, once the Finder is 
// running, only then patching DrawString/Text locally from there.
//
// Optimized to only update stored date strings for today and yesterday when the
// lo-mem global variable Time moves out of range previously noted for today's date.
//
// One quirk - this would probably also impact any cdevs running under Finder that 
// use DrawString/Text to show an abbreviated date.  I haven't tested this or tried 
// to correct for it.  (We do check to ensure not drawing into a DA window.)
//
// Tested under 6.0.8, 7.1, 7.5.5.
//==================================================================================

#include <Traps.h>
#include <LoMem.h>
#include <SetupA4.h>
#include <Packages.h>

#include "CrutchUtilities.h"

#define GOOD_INIT_ICON 128

DECLARE_PATCH(SystemEvent, short, (EventRecord *e));
DECLARE_PATCH(DrawString,  void,  (Str255 s));
DECLARE_PATCH(DrawText,    void,  (unsigned char *buf, short byteOff, short byteCount));

Boolean gInstalledPatches;

void UpdateDateInfo(void);

Boolean FindAndReplacePrefix(unsigned char *s, short strLen, 
	Str255 p, Str255 replaceWith, Str255 outStr);

Boolean FindAReplacableDateString(unsigned char *s, short strLen);

Str255 gScratchStr;
DateTimeRec gTodaysDate;
Str255 gTodaysDateStr;
Str255 gYesterdaysDateStr;

unsigned long gStartOfDaySecs;
unsigned long gEndOfDaySecs;

StringHandle gTodayWordStr;
StringHandle gYesterdayWordStr;

void UpdateDateInfo(void)
// called on INIT load or when new day has started to update date/time info
// assumes A4 has been set up
{
	unsigned long secs = Time;
		
	gStartOfDaySecs = secs - secs % (24L * 60 * 60);
	gEndOfDaySecs = gStartOfDaySecs + 24L * 60 * 60;

	Secs2Date(secs, &gTodaysDate);
	IUDateString(secs, abbrevDate, gTodaysDateStr);

	secs -= 24L * 60 * 60;  // one day in seconds
	IUDateString(secs, abbrevDate, gYesterdaysDateStr);		
}

pascal short PatchedSystemEvent(EventRecord *e)
{
	SetUpA4();
	
	if (!gInstalledPatches
		&& EqualStr(CurApName, FinderName))
	{
		// first time calling SystemEvent in the Finder?  install our DrawString/Text
		// patches then never do anything again
		
		INSTALL_PATCH(Tool, DrawString);
		INSTALL_PATCH(Tool, DrawText);

		gInstalledPatches = true;
	}
	
	// call original trap without tail patch	
	RESTORE_A4_AND_JUMP_TO_TOOLTRAP(SystemEvent);
}

Boolean FindAndReplacePrefix(unsigned char *s, short strLen, 
	Str255 p, Str255 replaceWith, Str255 outStr)
// 's' is a pointer to text data with length 'strLen'
//
// if s has prefix p, replace it with 'replaceWith' and write the result to outStr,
// then return true.  else do nothing and return false.
//
// outStr can be the same string as 'p' to save memory.
//
// don't move or purge memory so we can be passed a dereferenced unlocked StringHandle
// in replaceWith.
{
	register int i;
	
	if (strLen < p[0])
		return false;  // too short for prefix
	
	for (i = 1; i <= p[0]; i++)
		if (s[i - 1] != p[i])
			return false;
	
	// still here?  we found the prefix -- replace it:

	BlockMove(&replaceWith[1], &outStr[1], replaceWith[0]);  // copy the prefix

	if (strLen > p[0])  // if there's more, copy the rest
		BlockMove(&s[i - 1], &outStr[replaceWith[0] + 1], strLen - p[0]);

	outStr[0] = strLen - p[0] + replaceWith[0];
	return true;
}

Boolean FindAReplacableDateString(unsigned char *s, short strLen)
{
	// does our core work needed by both DrawString and DrawText patches:
	// 
	// 1. check if string length about right for a date or date-time before wasting time
	// 2. ensure thePort doesn't look like a DA window (of course it might not be
	//    a window at all and hence give us garbage windowKind, but in that case 
	//    ideally we wouldn't draw into it anyway, so bailing on a negative value
	//    there never hurts) -- we don't check FrontWindow since might need to redraw
	//    non-front windows on an update event
	// 3. update global date strings if needed based on Time global var
	// 4. if checks pass, call FindAndReplacePrefix, which checks the string we are 
	//    given vs. either prefix -- if a match, copies the string (with new "Today"
	//    or "Yesterday" prefix) into gScratchStr, return true
	// 5. otherwise, return false
	
	if (strLen >= 15 && strLen <= 35
		&& ((WindowPeek) THEPORT_FROM_CURRENTA5)->windowKind >= 0)
	{
		unsigned long secs = Time;

		// has date changed? (check for past dates as user could have changed date)
		
		if (secs < gStartOfDaySecs || secs >= gEndOfDaySecs)
			UpdateDateInfo();

		if (FindAndReplacePrefix(s, strLen, gTodaysDateStr, *gTodayWordStr, gScratchStr))
		{
			// we are drawing today's date, it's now in gScratchStr
			return true;
		}
		else
		{
			// not today; was it yesterday?					
			if (FindAndReplacePrefix(s, strLen, gYesterdaysDateStr, *gYesterdayWordStr, gScratchStr))
				return true;
		}
	}
	
	return false;
}

pascal void PatchedDrawString(Str255 s)
{
	SetUpA4();

	if (FindAReplacableDateString(&s[1], s[0]))
		// update the parameter on the stack; original _DrawString gets it below
		s = gScratchStr;

	// call original trap without tail patch	
	RESTORE_A4_AND_JUMP_TO_TOOLTRAP(DrawString);
}

pascal void PatchedDrawText(unsigned char *buf, short byteOff, short byteCount)
{
	SetUpA4();
	
	if (FindAReplacableDateString(buf + byteOff, byteCount))
	{
		// update parameters on the stack; original _DrawText gets them below
		buf = &gScratchStr[1];
		byteOff = 0;
		byteCount = gScratchStr[0];
	}
	
	// call original trap without tail patch	
	RESTORE_A4_AND_JUMP_TO_TOOLTRAP(DrawText);
}

void main(void)
{
	Ptr initPtr;
	Handle showIconCode;
	Handle initHndl;
		
	asm { move.l a0, initPtr }  // get pointer to ourselves
	
	RememberA0();
	SetUpA4();
	
	gInstalledPatches = false;
	
	// get handle to ourselves and check flags	

	if (ConfirmResourceWithFlags(
			initHndl = RecoverHandle(initPtr), 
			resSysHeap & resLocked)
		)
	{
		// (we set Locked bit in "Set Project Type..." (confirmed above) so don't need HLock here)
		DetachResource(initHndl);
		
		ConfirmResourceWithFlags(gTodayWordStr = GetString(128), resSysHeap);
		DetachResource((Handle) gTodayWordStr);
		
		ConfirmResourceWithFlags(gYesterdayWordStr = GetString(129), resSysHeap);
		DetachResource((Handle) gYesterdayWordStr);

		// set up global info
		UpdateDateInfo();
				
		// patch our trap -- we patch SystemEvent only so we can later patch DrawString
		// once the Finder is loaded (so our DrawString patch only impacts the Finder
		// and doesn't slow down anybody else)
		INSTALL_PATCH(Tool, SystemEvent);
	}
	
	// call ShowInitIcon code:
	
	if (showIconCode = Get1Resource('Code', -4048))
		((pascal void (*) (short, Boolean)) *showIconCode) (GOOD_INIT_ICON, true);
	else
		Complain("\pcouldn't get ShowInitIcon code resource");
	
	RestoreA4();
}
