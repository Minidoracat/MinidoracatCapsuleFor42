<!-- Steam discussion post source (English); the description is a summary, this thread is the reference -->
<!-- Thread URL: TBD after first upload -->
<!-- Title: 📖 Vehicle Capsule Guide: Packing, Unpacking & Recovery -->

[b]中文版：[/b] [url=TBD after first upload]Vehicle Capsule 完整說明：收車、展開與補回[/url]

Vehicle Capsule lets you pack a parked vehicle into a capsule and carry it around. Throw the capsule when you need the vehicle, and it appears exactly as it was, with its mods, condition and cargo. Packed vehicles are not in the world, so busy bases run smoother too. This thread covers every feature, the server settings, the admin tools and common questions.

[h2]🚀 Quick Start[/h2]
[olist]
[*] Get an empty capsule (loot, an admin or the Economy Center, see "Getting capsules" below)
[*] Park, turn the engine off, make sure nobody is inside, carry an empty capsule, then right-click the vehicle and choose [b]Pack into Capsule[/b]; after about 10 seconds the vehicle is packed and the capsule drops where the vehicle stood
[*] Pick up the capsule. When you need the vehicle, right-click the capsule in your inventory and choose [b]Throw Capsule[/b]; the cursor outlines the vehicle, and you left-click when the outline is green
[*] Capsule too heavy to pick up? Right-click it on the ground and choose [b]Press the Button[/b]; the vehicle appears next to it
[/olist]

[h2]🧰 Features[/h2]

[h3]Packing a vehicle[/h3]
[list]
[*] [b]The menu[/b]: right-click a vehicle and [b]Pack into Capsule[/b] is at the end of the menu. Hover the option to see each requirement: checked rows are met, the others tell you what to do, and the option stays grayed out until they are.
[*] [b]Requirements[/b]: engine off, nobody inside, an empty capsule in your inventory (bags count), and permission to pack this vehicle (next item). A vehicle that is towing or being towed, has animals in its trailer, or holds another loaded capsule can't be packed; the menu tells you why.
[*] [b]Who can pack[/b]:
[list]
[*] Vehicles claimed in Minidoracat Vehicle Manager: only the owner can pack; sharing a vehicle never grants packing. Admins must first turn on override in the Admin tab of the fleet window.
[*] Other vehicles (no Vehicle Manager, or not claimed): the sandbox option "Who can pack vehicles" decides. By default it is anyone carrying this vehicle's key (in the inventory or in the ignition); it can be changed to anyone or admins only.
[*] Admins are not limited by the sandbox option and can always pack these.
[/list]
[*] [b]Packing[/b]: takes about 10 seconds. The server checks permission, passengers and towing again and only packs when everything passes; it saves the vehicle and its cargo first and removes the vehicle from the world last. A key left in the ignition moves to your inventory.
[*] [b]Afterwards[/b]: the empty capsule is used up and a capsule named after the vehicle drops where the vehicle stood. The name is in the game language of the player who packed it. Nearby players see smoke and a flash and hear a sound.
[*] [b]What is saved[/b]: vehicle type, paint, every part and its condition (including mods and removed parts), fuel, tire pressure, battery, doors, windows and locks, the key ID, and the cargo in every container on the vehicle. Vanilla and modded vehicles such as KI5's work the same way.
[/list]

[h3]Throwing a capsule[/h3]
[list]
[*] [b]How[/b]: with the capsule on you, right-click it in the inventory and choose [b]Throw Capsule[/b] to get the landing cursor. Left-click to throw, right-click to cancel.
[*] [b]The landing cursor[/b]: outlines the vehicle on the ground. Green with "Fits: <vehicle>" means it fits; red shows the reason it doesn't: too far, can't see there, not loaded yet, another vehicle, a person, a tree, no ground to park on, furniture or other objects, a wall or fence, indoors. The spot must be within about 8 tiles of you and in sight.
[*] [b]Landing[/b]: the capsule flies to the spot, lands with smoke and a flash, and the vehicle appears as it was with its cargo back on board; the screen says "Unpacked: <vehicle>". With the sandbox option "Return an empty capsule after unpacking" on (the default), an empty capsule goes back into your inventory, ready for the next vehicle.
[*] [b]Ownership[/b]: with Vehicle Manager installed, the unpacked vehicle keeps its original owner.
[*] [b]Zombies are not affected[/b]: the smoke and flash are drawn on screen only, so zombies don't lose track of you; the capsule's pop doesn't attract zombies by default (servers can turn that on in the sandbox options).
[/list]

[h3]Press the Button (capsule on the ground)[/h3]
[list]
[*] [b]When[/b]: heavy cargo can make a capsule too heavy to pick up, and so too heavy to throw. Right-click the capsule on the ground (in the world or the loot window) and choose [b]Press the Button[/b].
[*] [b]How[/b]: your character walks to the capsule and the same landing cursor appears; the vehicle appears within about 3 tiles of the capsule. Left-click to press, right-click to cancel. The cargo goes back into the vehicle as usual.
[/list]

[h3]When there is no room[/h3]
[list]
[*] The cursor checks the spot before you throw, and the server checks it again on landing. If the spot got blocked in between (someone walked in, for example), no vehicle appears; a "No room for the vehicle here" window shows the reason.
[*] [b]Thrown[/b]: the capsule drops on the landing spot. Pick a clear spot and press the button on the ground, or pick it up and throw again.
[*] [b]Pressed[/b]: the capsule stays where it is; pick a clear spot and press again.
[*] The vehicle and the cargo stay in the capsule; nothing is lost because the spot was blocked.
[/list]

[h3]Cargo[/h3]
[list]
[*] [b]Kept as it was[/b]: everything in the vehicle's containers goes into the capsule as the original items, so water in bottles, items inside bags, blood and dirt on clothes and food freshness are all kept. On unpacking, items go back into their original container; if that is gone (the part was removed, for example) they go into another container on the vehicle with room, and whatever still doesn't fit lands on the ground next to it.
[*] [b]Weight counts[/b]: a capsule weighs the capsule itself plus all of its cargo, in your hands too. A capsule with heavy cargo can't be picked up; use Press the Button.
[*] [b]No taking cargo out directly[/b]: you get it by unpacking the vehicle. Dragging, Take All, eating and drinking, loading ammo and crafting never use what is inside a capsule, and you get the message "Unpack the vehicle to get this out". This also means a server rollback can't leave a second copy of the cargo. You can't put anything into a capsule either.
[*] [b]The server checks too[/b]: if cargo is taken out anyway, the server puts it back into the capsule within a second and logs it.
[/list]

[h3]Capsules that were already unpacked[/h3]
[list]
[*] Each capsule unpacks only once. After a normal unpack the loaded capsule is gone (replaced by an empty one when the option is on).
[*] If an already-unpacked capsule turns up again (the server rolled back to a save from before the unpack, or an admin already restored the vehicle), its tooltip shows its state, and throwing it shows "This capsule was already unpacked" with the record and the capsule number. If the vehicle is missing, give the number to an admin; they can see where the capsule went.
[*] Any cargo still inside such a capsule is a second copy; once the server knows the vehicle is in the world, it swaps the capsule for an empty one.
[*] "This capsule needs an admin" means the server stopped before the capsule's last change was saved. Give the number to an admin (see "Admins: unconfirmed after a crash" below).
[/list]

[h3]Tooltip and 3D preview[/h3]
[list]
[*] [b]Tooltip[/b]: hover a capsule and an extra box under the vanilla tooltip shows the vehicle name, type, paint, condition (engine and body), fuel, battery, missing parts, mods, cargo (count and the first items) and who packed it. The data comes from the server, so it says "Reading vehicle condition..." for a moment. For a capsule on the ground, walk closer to see the details.
[*] [b]Other states[/b]: an empty capsule tells you how to pack; already unpacked, restored by an admin, unconfirmed after a crash, or data missing on this server are all spelled out.
[*] [b]3D preview[/b]: right-click a capsule and choose [b]Preview vehicle[/b]. Left-drag to rotate, right-drag to pan, scroll to zoom, double-click to reset, or use the front, side and top view buttons.
[*] [b]It shows the model, not this vehicle[/b]: the preview draws the vehicle type's default look with every optional part, not this vehicle's actual paint and parts; the list next to it shows this vehicle's real state.
[/list]

[h3]Performance[/h3]
[list]
[*] Packed vehicles are not in the world, so the game spends no time on them each frame. The more vehicles you pack, and the heavier they are (KI5's vehicles, for example), the smoother things get nearby.
[*] What packing can't fix: vehicles being driven and vehicles that aren't packed cost the same as before, and the moment a vehicle is unpacked may hitch briefly.
[/list]

[h3]Getting capsules[/h3]
[list]
[*] [b]Loot[/b]: empty capsules show up in containers at mechanic shops, car supply stores and gas station repair bays; home garages are off by default. Servers can toggle each location and tune its weight (see the settings below).
[*] [b]Economy Center[/b]: with Minidoracat Economy installed, admins list the empty capsule (item ID [b]MinidoracatVehicleCapsule.Capsule[/b]) to sell it. Loaded capsules can't go on the market.
[*] [b]From admins[/b]: hand out empty capsules with the vanilla item list or the /additem command.
[/list]

[h2]⚙️ Server Settings (sandbox pages "Minidoracat Vehicle Capsule" and "Minidoracat Vehicle Capsule - Loot")[/h2]
[list]
[*] [b]Return an empty capsule after unpacking[/b]: on by default. After a capsule unpacks, an empty capsule goes back into the thrower's inventory.
[*] [b]Who can pack vehicles[/b]: "Key holders" by default (the key in the inventory or in the ignition); can be set to "Anyone" or "Admins only". Admins are never limited. With Vehicle Manager installed, claimed vehicles follow it instead and this option covers unclaimed vehicles.
[*] [b]Zombie attraction radius of the capsule sound[/b]: 0 tiles by default (0–50). 0 means the capsule's pop attracts no zombies.
[*] [b]Empty capsules appear as loot[/b]: on by default. Master switch; when off, none of the four locations below spawn empty capsules.
[*] [b]Mechanic shops[/b]: on by default, weight 0.5.
[*] [b]Car supply stores[/b]: on by default, weight 0.5.
[*] [b]Gas station repair bays[/b]: on by default, weight 0.3.
[*] [b]Home garages[/b]: off by default, weight 0.2.
[*] Weights go from 0 to 10 on the same scale as the vanilla loot tables; higher means more often. Loot settings only affect containers opened for the first time afterwards; containers already searched don't refill. Changes made while the server is running apply to containers opened from then on. The admin panel's "Loot" tab edits these same options.
[/list]

[h2]🛡️ Admins[/h2]

[h3]Admin panel[/h3]
[list]
[*] [b]Opening it[/b]: admins see a Vehicle Capsule button on the family toolbar that opens [b]Vehicle Capsule Admin[/b]. It can be hidden in the options. Regular players don't see it.
[*] [b]Records[/b]: search by capsule number or player name and filter by state (packed, unpacked, restored, voided, unconfirmed after a crash). Select a record to see its timeline (every pack, unpack, refusal, restore and verdict with time and player), its cargo list and its recorded spot.
[*] [b]Go to the recorded spot[/b]: teleports you next to the record's location, so you can check on site whether the vehicle is there.
[*] [b]Loot[/b]: the on/off switch and weight of each of the four locations; after [b]Apply[/b], newly opened containers follow the new settings right away. Requires the right to change sandbox settings.
[*] Every pack, unpack, refusal, restore and verdict is written to the capsule records and the server log.
[/list]

[h3]Restoring a vehicle[/h3]
[list]
[*] [b]When[/b]: the capsule is gone (lost by the player, removed by a cleanup mod, or this mod was removed and reinstalled), or a server rollback made the vehicle disappear. When a player dies, the capsule stays on the body or on the ground; if it can be found, there's nothing to restore.
[*] [b]How[/b]: select the capsule in the records, use [b]Go to the recorded spot[/b] first, make sure nothing is in the way, then press [b]Restore vehicle[/b]. The vehicle appears at the recorded spot (where it was last packed or unpacked) with its saved condition. Records that are unconfirmed after a crash need [b]I checked on site[/b] ticked first.
[*] [b]The cargo doesn't come back[/b]: the cargo lived inside the capsule and is gone with it. The record lists the cargo types and counts; whether to hand anything out is up to the admin, and you can leave a note (for example "replaced the water bottles").
[*] [b]Never an extra vehicle[/b]: restoring makes the original capsule void at the same time, so it can't be unpacked even if it turns up later. If the server can find the recorded vehicle in the world, the restore is refused.
[/list]

[h3]Unconfirmed after a crash[/h3]
[list]
[*] The server marks a record as saved about 5 seconds after a pack or unpack. If the server crashes within those seconds, the record shows as "Unconfirmed (crash)" after the restart; the capsule can't be unpacked for now, and the player sees "This capsule needs an admin".
[*] [b]Deciding[/b]: select the record, check on site, tick [b]I checked on site[/b], then press:
[list]
[*] [b]Car is there, close[/b]: the vehicle is in the world. A pack record is voided (the original vehicle is still there); an unpack record stays as it is.
[*] [b]Car is gone[/b]: a pack record can be restored as usual; an unpack record goes back to packed, so the player throws the capsule again and gets both the vehicle and the cargo back. If the server can find the vehicle, "Car is gone" is refused.
[/list]
[*] When a record is confirmed saved and the vehicle has been unpacked, the server clears the extra cargo out of that capsule and swaps it for an empty one. Unconfirmed capsules are left alone, because their cargo may be the only copy.
[/list]

[h3]Recommended setup[/h3]
[list]
[*] [b]With Minidoracat Cleaner[/b]: add [b]MinidoracatVehicleCapsule.LoadedCapsule[/b] to its "Protected item list" sandbox option so loaded capsules on the ground are never cleaned up. Please exclude this item in any other mod that cleans up ground items, too.
[*] [b]Back it up[/b]: every capsule's record and vehicle data live in the server's [b]Zomboid/Lua/MinidoracatVehicleCapsule/[/b] folder, not in the world save. If that folder is deleted, packed vehicles can't be restored, so back it up together with the world save.
[/list]

[h2]⚠️ Known Limitations[/h2]
[list]
[*] The 3D preview draws the vehicle type's default look, not the actual paint and parts.
[*] Vehicles that are towing or being towed, carry animals in a trailer, have the engine running or have someone inside can't be packed.
[*] Capsules don't unpack indoors; a thrown capsule must land within about 8 tiles and in sight, and a pressed one puts the vehicle within about 3 tiles of the capsule.
[*] If a vehicle mod is removed, capsules holding its vehicles can't unpack (the tooltip says the server doesn't have this vehicle type); they work again once the vehicle mod is back.
[*] Loaded capsules can't be put on the Economy market.
[*] A capsule's name is in the game language of the player who packed it and doesn't change for other players; the tooltip and preview use your own language.
[*] Restoring brings back the vehicle, not the cargo; the server only finds vehicles that are loaded nearby, so check on site before deciding.
[*] This mod doesn't track the vehicle after it is unpacked; use Vehicle Manager for owners and locations.
[/list]

[h2]❓ FAQ[/h2]
[list]
[*] [b]Removing this mod?[/b] Unpack every capsule first, then remove it. Capsules that are still packed disappear along with their cargo. The server records remain, so if you reinstall the mod later, admins can restore the vehicles from the admin panel, but not the cargo.
[*] [b]My capsule is gone. What now?[/b] Check bodies, the ground and the vehicle containers first. If it's really gone, give an admin the capsule number (shown in the tooltip or dialog) or your name; the admin can see where the capsule went and restore the vehicle (the cargo doesn't come back).
[*] [b]What happens to capsules after a server crash?[/b] Mostly nothing. If the crash came within a few seconds of a pack or unpack, the capsule says it needs an admin; give the number to an admin. After the admin checks on site, the vehicle and the capsule end up in the right state, with no extra vehicle and no second copy of the cargo.
[*] [b]Why can't I take things out of a capsule?[/b] By design you unpack the vehicle to get them, so a crash can never create a second copy of the cargo.
[*] [b]I can't pick up the capsule.[/b] The cargo is too heavy. Right-click the capsule on the ground and choose [b]Press the Button[/b] to unpack it right there.
[*] [b]Can I pack someone else's vehicle?[/b] A vehicle claimed in Vehicle Manager: only its owner (admins need override on). Other vehicles depend on the server: by default you need the vehicle's key, and admins always can.
[*] [b]I threw it and no vehicle appeared.[/b] The landing spot was blocked when it landed; a window shows the reason and the capsule is on the landing spot. Pick a clear spot and press the button on the ground, or pick it up and throw again.
[*] [b]Is it safe in multiplayer?[/b] Packing, unpacking and restoring are all validated by the server; the vehicle data lives only on the server, and the capsule itself only carries its name.
[/list]

[h2]💬 Reporting[/h2]
[list]
[*] GitHub Issues: https://github.com/Minidoracat/MinidoracatVehicleCapsuleFor42/issues
[*] Discord: https://discord.gg/Gur2V67
[/list]
Please include your game version, mod list, the vehicle, and what happened (packing or unpacking, single player or multiplayer, and the capsule number from any dialog). Please report translation issues too.
