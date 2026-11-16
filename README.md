# Event Notifier

A small Retail WoW addon for Midnight world-event and Timewalking text alerts. No libraries or dependencies.

Notifications appear as achievement-style banners with an event icon, a dark title strip, parchment background, event timestamp, and countdown when timing data is available. Up to four banners stack vertically; additional alerts wait in a queue. Each banner displays for eight seconds and fades out. The full notification also appears in chat.

1. Enable **Event Notifier** in WoW's AddOns list, then log in or `/reload`.
2. On a fresh install the selection window opens automatically after entering the world. Check the events you want. Reopen it any time with `/en` (or `/eventnotifier`).
3. Use **Test Alert** or `/en test` to preview the on-screen and chat message.

Nothing is selected on a fresh install. Choices and the enable toggle save automatically for your account. Selected events already available when you log in or check them also trigger an alert. Repeat updates for the same occurrence are suppressed, including across `/reload`.

The initial checklist includes:

- **Void Assaults:** Void Strikes and Void Incursions in Eversong Woods / Zul'Aman.
- **Aqir Invasions:** the ten-minute hourly event in the active invasion zone.
- **Stormarion Assault:** the public defense event in Voidstorm.
- **Abundance: Abundant Harvest:** the rotating empowered cave, rather than the ordinary cave entrances.
- **Curse Surges:** the rotating public events on the Coiled Isle.
- **Timewalking:** alerts when a Timewalking dungeon event is active in Blizzard's in-game calendar.

The selection window shows each event's reminder timing. Recurring world events notify for each occurrence: Aqir Invasions at the start of each hour, assaults and surges when they become available, and Abundant Harvest when its location rotates. Duplicate updates and reloads during the same occurrence do not repeat the alert.

The options window has three top-level tabs. **Expansions → Midnight** contains the five Midnight world events. **Holidays** is empty for now. **General** contains Timewalking. Event selections and the enable toggle apply across tabs and save automatically.

To position the banners, open **General → Move Notifications** (or type `/en move`). Drag the preview window to the desired location, then click **Done**. The saved location survives reloads and logins and scales with the UI size. **Reset Position** restores the default. Live banners are click-through; the positioning preview captures dragging only while unlocked. Notifications arriving while positioning wait until you click Done. **Test Alert** previews a real banner at the chosen location.

Only **Aqir Invasions** and **Curse Surges** have **Enable early reminder** controls. Select the event, enable its early reminder, and choose **1–10 minutes** before its start (default: 5). Press Enter or click outside the minutes field to save it. Each event has its own setting, saved across logins. Early reminders are off by default. Upgrading clamps saved minute values to this range and disables any old early reminders for other events, while preserving event selections.

Early reminders use start times supplied by the game and Aqir's hourly invasion window. They work while you are online; logging in inside the reminder window gives one reminder with the minutes remaining. Each occurrence warns once, and its normal start notification still applies. Events visible only as live markers cannot give advance warning until the game supplies a start time; their availability notifications continue as usual. Timewalking keeps its daily login reminder and has no early reminder.

Timewalking is an all-day event. While active, it reminds you on your first login of each realm calendar day, once per day across your account's characters and `/reload`. Selecting an active Timewalking event can also give that day's reminder immediately. Staying online past midnight does not trigger another daily reminder; log in again on the new day. Existing selections are preserved when upgrading.

Timewalking uses the realm's calendar dates and the event's exact start/end times. The calendar UI does not need to be open. Private player/guild events with "Timewalking" in the title do not trigger this notification.

It reads Blizzard's event schedule and current map markers, updates when the game reports changes, and sets a timer for the next known event boundary. Aqir entries that describe a weekly zone rotation are narrowed to the first ten minutes of each hour. Availability depends on the event data WoW exposes to your character, including unlocks and phasing; a scheduled window does not guarantee a boss is still alive on your shard. **Refresh** requests another read of the game's data.

The interface is English. Known numeric POI IDs identify Aqir, Stormarion, Harvest, and Curse Surge events across client languages; Void Assault detection currently uses event names or atlas tags containing `Void Assault`, `Void Strike`, or `Void Incursion`.

Other Midnight activities include Saltheril's Soiree, Legends of the Haranir, Ritual Sites, and Abyss Anglers. This first checklist focuses on recurring public event availability; it does not track weekly quest completion or player-started instances.

Sources: Blizzard's [launch activities](https://worldofwarcraft.blizzard.com/en-gb/news/24223312/midnight-nuevas-actividades-para-todos), [Void Assaults](https://news.blizzard.com/en-gb/article/24267938/take-a-look-ahead-at-the-12-0-5-content-update), [Aqir Invasions](https://worldofwarcraft.blizzard.com/en-us/news/24307306/midnight-s-12-1-5-content-update-is-now-live), and [Curse Surges](https://news.blizzard.com/en-gb/article/24293963/follow-the-snakes-to-the-coiled-isle-for-new-adventures). API shapes were checked against the client-generated [event scheduler documentation](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/EventSchedulerUIDocumentation.lua) and [POI documentation](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/AreaPoiInfoDocumentation.lua). Initial known POI IDs were cross-checked with the installed HandyNotes: Midnight event tables and Krowi Achievement Filter's Midnight event data.

## Validation

Offline validation uses Lua 5.1 with mocked WoW APIs. The options checks cover tab navigation, selection persistence, early-reminder controls and migration, daily login reminders, hourly Aqir reminders, Curse Surge timing, and duplicate suppression. Actual WoW rendering and live event detection still require an in-game check: open `/en`, switch between the tabs, select an event, use **Test Alert**, and verify an actual event start and `/reload`.

Timewalking's API fields were checked against Blizzard's client-generated [calendar documentation](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/CalendarDocumentation.lua) and [realm date/time documentation](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/DateAndTimeDocumentation.lua). Calendar tests cover active/upcoming/expired holidays, exact boundaries, asynchronous updates, a different viewed month, restricted data, and duplicate suppression.

## Releases

The GitHub Actions workflow follows TODO-Planner's BigWigs packager setup. Pushes to `main` and tags build an addon ZIP, available in the workflow's artifacts. Version tags also publish a GitHub release. `.pkgmeta` keeps the install folder named `Event-Notifier` and excludes tests and development tooling.

Commit the addon files first and start with a clean working tree. Then run:

```powershell
.\release.ps1 -minor
# Or: .\release.ps1 -major
```

The script bumps `Event-Notifier.toc`, commits the version change, creates an annotated `vX.Y.Z` tag, and pushes the branch and tag to `origin`. `-m` / `-M` are shortcuts for minor / major. With no argument it prompts for the bump type. Releases from `main` use the same workflow as TODO-Planner.

For CurseForge publishing, set the repository Actions variable `CURSEFORGE_PROJECT_ID` to **Event Notifier's** project ID and add the Actions secret `CURSEFORGE_KEY` with your API token. Until configured, the workflow builds ZIPs and publishes tagged GitHub releases without uploading to CurseForge. The workflow uses GitHub's built-in token for GitHub releases.
