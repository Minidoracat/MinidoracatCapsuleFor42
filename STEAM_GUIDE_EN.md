<!-- Steam guide source (English): the full reference for this mod; the Workshop description only summarizes. Format and sync: pz-family-docs/release.md「完整說明：Steam 指南」 -->
<!-- 標題：📖 Universal Capsule Mod Guide: Packing, Unpacking & Recovery -->
<!-- 摘要：Guide to the Minidoracat Universal Capsule mod: getting empty capsules, packing vehicles and animals, throwing to capture, throwing capsules and Press the Button, safehouse protection, cargo and what animals keep, the tooltip and 3D preview, trading vehicles and animals in the Economy Center, plus sandbox options, the admin panel, restoring vehicles and animals and what happens after a crash. -->
=== 🚀 Quick start
[b]繁體中文版：[/b][url=https://steamcommunity.com/sharedfiles/filedetails/?id=GUIDE_ZH]萬用膠囊 MOD 完整說明[/url]

The mod on Steam Workshop:
https://steamcommunity.com/sharedfiles/filedetails/?id=WORKSHOP_ID

Universal Capsule lets you pack a parked vehicle or a live animal into a capsule and carry it around. Throw the capsule when you need it: a vehicle appears exactly as it was, with its mods, condition and cargo, and an animal comes back just as you packed it. Packed vehicles are not in the world, so busy bases run smoother too.
[olist]
[*] [b]Get an empty capsule[/b]: loot, an admin or the Economy Center; see "Getting capsules".
[*] [b]Pack[/b]: park, turn the engine off, make sure nobody is inside, carry an empty capsule, then right-click the vehicle and choose "Pack into Capsule". After about 10 seconds the vehicle is packed and the capsule drops where the vehicle stood.
[*] [b]Pack an animal[/b]: right-click a live animal, open that animal's submenu and choose "Pack into Capsule"; see "Packing an animal".
[*] [b]Throw to capture[/b]: right-click an empty capsule in your inventory, choose "Throw to Capture" and throw it at an animal or a vehicle to pack it; see "Throwing to capture".
[*] [b]Throw[/b]: pick up the capsule. When you need the vehicle, right-click the capsule in your inventory and choose "Throw Capsule"; the cursor outlines the vehicle, and you left-click when the outline is green.
[*] [b]Too heavy to pick up?[/b] Right-click it on the ground and choose "Press the Button"; the vehicle appears next to it.
[/olist]
=== 🧰 Getting capsules
[list]
[*] [b]Loot[/b]: all seven kinds of empty capsule show up in containers at mechanic shops, car supply stores and gas station repair bays; home garages are off by default. Each location's share is split evenly over the types that are on. Servers can toggle each location and tune its weight; see "Sandbox options and defaults".
[*] [b]Economy Center[/b]: with Minidoracat Economy installed, admins list the empty capsule (item ID [b]MinidoracatCapsule.Capsule<Type>[/b], for example CapsuleCartoon) to sell it; "List..." in the admin panel's "Types" tab opens a product draft for that capsule in the Economy Center.
[*] [b]Capsules holding a vehicle or an animal[/b]: can be listed or auctioned too; see "Trading vehicles and animals in the Economy Center".
[*] [b]From admins[/b]: hand out empty capsules with the vanilla item list or the /additem command.
[/list]
[h3]Seven capsule types[/h3]
[list]
[*] [b]Types[/b]: Cartoon, Realistic, Dust, Steam, Sci-Fi, Magic and Shockwave. The end cap color tells the type; a loaded capsule adds a patterned band.
[*] [b]Same function[/b]: requirements, time, permission and records are the same; only the look, the smoke and the four sounds (throw, pop, pack, button) differ.
[*] [b]Everyone sees the same type[/b]: the type you pack with is the smoke nearby players see when packing, throwing and unpacking.
[*] [b]After unpacking[/b]: the empty capsule you get back is the same type.
[*] [b]A type an admin switched off[/b]: can't pack vehicles or animals any more; loaded ones still throw and unpack with the button. Its empty capsule's tooltip says so.
[/list]
=== 🧰 Packing a vehicle
[h3]Menu and requirements[/h3]
[list]
[*] [b]The menu[/b]: right-click a vehicle and "Pack into Capsule" is at the end of the menu.
[*] [b]Each requirement listed[/b]: hover the option; checked rows are met, the others tell you what to do, and the option stays grayed out until they are.
[*] [b]Requirements[/b]:
[list]
[*] Engine off
[*] Nobody inside
[*] An empty capsule in your inventory (bags count) of a type an admin has not switched off
[*] Permission to pack this vehicle (see "Who can pack")
[*] The vehicle is not in someone else's safehouse (see "Safehouse protection")
[/list]
[*] [b]Can't be packed[/b]: a vehicle that is towing or being towed, has animals in its trailer, or holds another loaded capsule; the menu tells you why.
[*] [b]Choosing a type[/b]: with empty capsules of two or more types, "Pack into Capsule" opens a submenu with one entry per type (for example "Steam Capsule ×1"); the tooltip title says "Pack into Steam Capsule".
[/list]
[h3]Who can pack[/h3]
[list]
[*] [b]Vehicles claimed in Minidoracat Vehicle Manager[/b]: only the owner and players the owner shared Tow with can pack (a share with everyone never includes Tow).
[*] [b]Admins and claimed vehicles[/b]: must first turn on override in the Admin tab of the fleet window.
[*] [b]Without permission[/b]: the option has a minus mark, the tooltip row says why, and clicking it shows a notification.
[*] [b]Other vehicles[/b] (no Vehicle Manager, or not claimed): the sandbox option "Who can pack vehicles" decides. By default it is anyone carrying this vehicle's key (in the inventory or in the ignition); it can be changed to anyone or admins only.
[*] [b]Admins[/b]: not limited by this sandbox option and can always pack these.
[/list]
[h3]Packing[/h3]
[list]
[*] [b]Time[/b]: about 10 seconds.
[*] [b]The server checks again[/b]: permission, passengers and towing; it only packs when everything passes, saves the vehicle and its cargo first and removes the vehicle from the world last.
[*] [b]Key[/b]: a key left in the ignition moves to your inventory.
[*] [b]Afterwards[/b]: the empty capsule you used becomes a loaded capsule of the same type and drops where the vehicle stood.
[*] [b]Capsule name[/b]: "Type: vehicle", for example "Steam Capsule: Chevalier D6"; every player sees it in their own game language once the inventory or loot window lists it.
[*] [b]Effects[/b]: nearby players see that type's smoke and flash and hear its sound.
[/list]
[h3]What is saved[/h3]
[list]
[*] Vehicle type, paint
[*] Every part and its condition (including mods and removed parts)
[*] Fuel, tire pressure, battery
[*] Doors, windows and locks, the key ID
[*] The cargo in every container on the vehicle
[/list]
Vanilla and modded vehicles such as KI5's work the same way.
=== 🧰 Packing an animal
[h3]Menu and requirements[/h3]
[list]
[*] [b]The menu[/b]: right-click a live animal in the world. The vanilla menu has one entry per animal; open that animal's submenu and "Pack into Capsule" is at the end.
[*] [b]Each requirement listed[/b]: hover the option; the tooltip shows the empty capsule in your inventory and the animal's state, says what is wrong, and the option stays grayed out until it's fixed.
[*] [b]Requirements[/b]:
[list]
[*] An empty capsule in your inventory (bags count) of a type an admin has not switched off
[*] The server has "Allow packing animals" on
[*] The animal is alive and out in the world (not being carried, not in a hutch or a trailer)
[*] No rope on it (untie it first)
[*] You are not in a vehicle
[*] The animal is not in someone else's safehouse (see "Safehouse protection")
[/list]
[*] [b]Can't be packed[/b]: dead animals and animals on a butcher hook.
[*] [b]Who can pack[/b]: any player, no key or permission needed; tame or wild, young or grown.
[*] [b]Choosing a type[/b]: with empty capsules of two or more types, "Pack into Capsule" opens a submenu with one entry per type.
[*] [b]Rather not walk up?[/b] Throw an empty capsule at it instead; see "Throwing to capture". Wild animals run from people they see, so throwing is the easier way to catch them.
[/list]
[h3]Packing[/h3]
[list]
[*] [b]Time[/b]: your character walks next to the animal, then about 10 seconds; the animal stays put meanwhile.
[*] [b]The server checks again[/b]: the animal's state, the switch and the empty capsule; it only packs when everything passes, saves the animal first and removes it from the world last.
[*] [b]Afterwards[/b]: the empty capsule you used becomes a loaded capsule of the same type and drops where the animal stood.
[*] [b]Capsule name[/b]: "Type: name"; an unnamed animal goes by its breed and kind the vanilla way. Every player sees it in their own game language.
[*] [b]Wild animals[/b]: a wild animal that can be domesticated (a wild rabbit, for example) becomes tame when packed, just like picking it up in vanilla; animals that can't be domesticated, such as deer, stay wild.
[*] [b]Weight[/b]: the animal is not inside the capsule, so a capsule holding one weighs the same as an empty one.
[/list]
[h3]What is kept[/h3]
[list]
[*] Name, breed, sex
[*] Age, size and weight
[*] Health, hunger and thirst, stress
[*] Genes and genetic disorders
[*] Milk, wool
[*] Pregnancy and fertilization, and how far along they are
[/list]
[h3]What is not kept[/h3]
[list]
[*] [b]Time stands still in a capsule[/b]: a packed animal doesn't grow, get hungry or move along in a pregnancy; it comes out just as it went in.
[*] [b]Vanilla timers restart[/b]: the milking and petting intervals, the eggs laid that day, and breeding cooldowns.
[*] [b]Herd[/b]: which herd a wild animal belonged to is not kept.
[*] [b]Coat pattern (multiplayer)[/b]: vanilla lets each player's game pick the pattern, so after release different players may see different patterns.
[/list]
[h3]When an admin switches animal packing off[/h3]
[list]
[*] [b]The switch[/b]: the sandbox option "Allow packing animals" (on by default), also in the admin panel's "Settings" tab.
[*] [b]When off[/b]: the option is grayed out with "An admin switched off packing animals"; throwing to capture can't take animals either (vehicles still can).
[*] [b]Capsules already holding an animal[/b]: can still be thrown, pressed and restored by admins.
[/list]
=== 🧰 Throwing and pressing
[h3]Throwing a capsule[/h3]
[list]
[*] [b]How[/b]: with the capsule on you, right-click it in the inventory and choose "Throw Capsule" to get the landing cursor. Left-click to throw, right-click to cancel.
[*] [b]Landing spot[/b]: within about 8 tiles of you and in sight.
[*] [b]Green outline[/b]: the vehicle's footprint on the ground, with "Fits: <vehicle>" when it fits.
[*] [b]Red outline[/b]: it doesn't fit, with the reason: too far, can't see there, not loaded yet, another vehicle, a person, a tree, no ground to park on, furniture or other objects, a wall or fence, indoors, the spot is in someone else's safehouse.
[/list]
[h3]Landing[/h3]
[list]
[*] [b]Unpacking[/b]: the capsule whooshes to the spot, lands with a pop, smoke and a flash, and the vehicle appears as it was with its cargo back on board; the screen says "Unpacked: <vehicle>".
[*] [b]Empty capsule back[/b]: with the sandbox option "Return an empty capsule after unpacking" on (the default), an empty capsule of the same type goes back into your inventory, ready for the next vehicle.
[*] [b]Ownership[/b]: with Vehicle Manager installed, the unpacked vehicle is reattached to its original claim: the owner and the shared list stay the same and the old key still opens the doors.
[*] [b]While packed[/b]: the fleet window shows "Claimed - not here right now"; Vehicle Manager's inactivity release still counts, so an owner who stays offline too long loses the claim just as with a parked vehicle.
[*] [b]Zombies are not affected[/b]: the smoke and flash are drawn on screen only, so zombies don't lose track of you; the capsule's pop doesn't attract zombies by default (servers can turn that on in the sandbox options).
[/list]
[h3]Press the Button (capsule on the ground)[/h3]
[list]
[*] [b]When[/b]: heavy cargo can make a capsule too heavy to pick up, and so too heavy to throw.
[*] [b]How[/b]: right-click the capsule on the ground (in the world or the loot window) and choose "Press the Button". Your character walks to the capsule and the same landing cursor appears; left-click to press, right-click to cancel.
[*] [b]Where the vehicle appears[/b]: within about 3 tiles of the capsule.
[*] [b]Cargo[/b]: goes back into the vehicle as usual.
[/list]
[h3]When there is no room[/h3]
[list]
[*] [b]Two checks[/b]: the cursor checks the spot before you throw, and the server checks it again on landing.
[*] [b]Blocked in between[/b] (someone walked in, for example): no vehicle appears; a "No room for the vehicle here" window shows the reason.
[*] [b]Thrown[/b]: the capsule drops on the landing spot. Pick a clear spot and press the button on the ground, or pick it up and throw again.
[*] [b]Pressed[/b]: the capsule stays where it is; pick a clear spot and press again.
[*] [b]Nothing is lost[/b]: the vehicle and the cargo stay in the capsule.
[/list]
=== 🧰 Releasing an animal
[list]
[*] [b]Throwing[/b]: same as a vehicle: right-click the capsule in your inventory and choose "Throw Capsule"; the spot must be within about 8 tiles of you and in sight, and the cursor marks a single square.
[*] [b]Press the Button[/b]: right-click the capsule on the ground and choose "Press the Button"; the animal appears on the square you pick within about 3 tiles of the capsule.
[*] [b]Landing spot[/b]: one free square is enough. Water, under a vehicle, a tree, no ground, something in the way or an area not loaded yet won't do; indoors is fine.
[*] [b]Landing[/b]: the capsule lands with smoke and a flash, the animal appears as it was, and the screen says "Unpacked: <name>".
[*] [b]Empty capsule back[/b]: with "Return an empty capsule after unpacking" on (the default), an empty capsule of the same type goes back into your inventory.
[*] [b]No room[/b]: if the spot is blocked on landing, no animal appears and a "No room for the animal here" window gives the reason. A thrown capsule drops on the spot and a pressed one stays where it is; try another free square, the animal is still in the capsule.
[*] [b]No 3D preview[/b]: a capsule holding an animal has no "Preview vehicle" in its menu.
[/list]
=== 🧰 Throwing to capture
[h3]How to throw[/h3]
[list]
[*] [b]The menu[/b]: with an empty capsule on you (bags count), right-click it in the inventory and choose "Throw to Capture" to get the capture cursor. Left-click to throw, right-click to cancel.
[*] [b]Target[/b]: an animal or a vehicle on the square under the cursor or right next to it; any square of a vehicle's body counts. With both an animal and a vehicle there, the animal comes first.
[*] [b]Range[/b]: the spot you aim at must be within about 8 tiles of you and in sight.
[*] [b]Green outline[/b]: marks the target (the animal's square or the whole vehicle) with "Capture: <name>".
[*] [b]Red outline[/b]: it can't be captured, with the reason: no animal or vehicle there, too far, can't see there, an admin switched off packing animals or this capsule type, in someone else's safehouse, or the same state and permission reasons as packing from the menu.
[/list]
[h3]What can be captured[/h3]
[list]
[*] [b]Animals[/b]: the same requirements as the menu: alive, out in the world, no rope, and "Allow packing animals" on. Tame or wild, young or grown; a wild animal that can be domesticated becomes tame when captured.
[*] [b]Vehicles[/b]: the same permission as packing from the menu (Tow shared in Vehicle Manager, or the sandbox option "Who can pack vehicles", by default the vehicle's key), and the engine off, nobody inside and no trailer.
[*] [b]No walking up[/b]: it's just the throw, without the 10 seconds of packing.
[*] [b]Best for wild animals[/b]: wild animals run from people they see, so packing from the menu means getting right next to them; a throw works from a distance.
[/list]
[h3]Hit or miss[/h3]
[list]
[*] [b]Two checks[/b]: the cursor and the server check before the throw; on landing the server looks for the target again within one square of the spot and checks the rules again.
[*] [b]Captured[/b]: the empty capsule flies over, the packing smoke rises at the target and it goes into the capsule. The loaded capsule lies where the target stood and the screen says "Captured: <name>"; go and pick it up.
[*] [b]Refused before the throw[/b]: the capsule doesn't leave your hand; the screen gives the reason and "The empty capsule is still in your inventory."
[*] [b]Missed[/b]: the capsule takes a moment from release to landing. If the target moves more than a square away from where you aimed, dies, is picked up, or someone gets into the vehicle in that time, the throw misses. The empty capsule lies on the landing spot and the screen says "Nothing captured: <reason>"; pick it up and throw again.
[*] [b]Landing spot in someone else's safehouse[/b]: a missed empty capsule falls at your feet instead.
[/list]
=== 🧰 Safehouse protection
[list]
[*] [b]The rule[/b]: on a multiplayer server, nobody can pack, capture or release a vehicle or an animal in someone else's safehouse. Who is exempt follows vanilla: the safehouse owner and members, staff with the vanilla safehouse permission, and safehouse war time.
[*] [b]Single player[/b]: there are no safehouses, so nothing changes.
[/list]
[h3]Packing and capturing[/h3]
[list]
[*] [b]Squares checked[/b]: the animal's square; for a vehicle, every square under its body, and one square inside someone else's safehouse is enough to refuse.
[*] [b]From the menu[/b]: the option is grayed out with "in someone else's safehouse".
[*] [b]Throw to capture[/b]: the cursor turns red with the same reason and the capsule is not thrown.
[/list]
[h3]Releasing[/h3]
[list]
[*] [b]Squares checked[/b]: the landing ground of a throw or a press (the vehicle's footprint or the animal's square); one square inside someone else's safehouse is enough, and the cursor says "the spot is in someone else's safehouse".
[*] [b]Refused before the throw[/b]: the capsule is not thrown and stays in your inventory; a pressed one stays where it is.
[*] [b]Refused on landing[/b] (rare): a thrown capsule falls at your feet, never inside someone else's safehouse; a pressed one stays where it is. The vehicle or animal is still in the capsule.
[*] [b]Admin restore[/b]: refused when the chosen spot is in someone else's safehouse; see "Restoring a vehicle or an animal".
[/list]
=== 🧰 Cargo
[h3]Kept as it was[/h3]
[list]
[*] [b]The original items go in[/b]: everything in the vehicle's containers goes into the capsule, so water in bottles, items inside bags, blood and dirt on clothes and food freshness are all kept.
[*] [b]On unpacking[/b]: items go back into their original container.
[*] [b]Original container gone[/b] (the part was removed, for example): they go into another container on the vehicle with room, and whatever still doesn't fit lands on the ground next to it.
[*] [b]Weight counts[/b]: a capsule weighs the capsule itself plus all of its cargo, in your hands too. A capsule with heavy cargo can't be picked up; use Press the Button.
[/list]
[h3]Unpack to get it out[/h3]
[list]
[*] [b]No taking cargo out directly[/b]: dragging, Take All, eating and drinking, loading ammo and crafting never use what is inside a capsule, and you get the message "Unpack the vehicle to get this out".
[*] [b]Why[/b]: this means a server rollback can't leave a second copy of the cargo.
[*] [b]No putting in[/b]: you can't put anything into a capsule either.
[*] [b]The server checks too[/b]: if cargo is taken out anyway, the server puts it back into the capsule within a second and logs it.
[/list]
[h3]When the server allows taking cargo out[/h3]
With the sandbox option "Allow taking cargo out of capsules" on:
[list]
[*] [b]Works directly[/b]: dragging, Take All, eating and drinking and loading ammo work straight from the capsule.
[*] [b]Crafting and building[/b]: still don't use what is inside, so take it out first.
[*] [b]Out only[/b]: items can only be taken out, never put in.
[*] [b]Still locked[/b]: a freshly packed capsule opens after about 5 seconds, and a capsule waiting for an admin stays locked.
[*] [b]Taken items[/b]: are removed from the record, so the tooltip, the preview and the admin panel list what is still inside, and only that comes back with the vehicle.
[/list]
=== 🧰 Already-unpacked capsules
[list]
[*] [b]Unpacks only once[/b]: after a normal unpack the loaded capsule is gone (replaced by an empty one of the same type when the option is on).
[*] [b]An unpacked capsule turns up again[/b] (the server rolled back to a save from before the unpack, or an admin already restored the vehicle): its tooltip shows its state, and throwing it shows "This capsule was already unpacked" with the record and the capsule number.
[*] [b]Vehicle missing[/b]: give the number to an admin; they can see where the capsule went.
[*] [b]Cargo still inside[/b]: it is a second copy; once the server knows the vehicle is in the world, it swaps the capsule for an empty one of the same type.
[*] [b]Rollback and no vehicle found[/b]: if the server rolled back to a save from before the unpack and the vehicle can't be found nearby, the capsule is put on hold for an admin instead (see "Unconfirmed after a crash"); its cargo is not cleared.
[*] [b]"This capsule needs an admin"[/b]: the server stopped before the capsule's last change was saved. Give the number to an admin (see "Unconfirmed after a crash").
[/list]
=== 🧰 Tooltip and 3D preview
[h3]Tooltip[/h3]
[list]
[*] [b]Where[/b]: hover a capsule and an extra box appears under the vanilla tooltip.
[*] [b]It lists[/b]: the type (look and sounds), the vehicle name, type, paint, condition (engine and body), fuel, battery, missing parts, mods, cargo (count and the first items) and who packed it.
[*] [b]Loading[/b]: the data comes from the server, so it says "Reading vehicle condition..." for a moment.
[*] [b]Capsules on the ground[/b]: walk closer to see the details.
[*] [b]Other states[/b]: an empty capsule tells you its type and how to pack, with a "!" line when an admin switched its type off; already unpacked, restored by an admin, unconfirmed after a crash, or data missing on this server are all spelled out.
[/list]
[h3]Capsules holding an animal[/h3]
[list]
[*] [b]It lists[/b]: the type, the animal's kind and breed, name, sex, age, weight, health, milk (when it can be milked), wool (when it has some), whether it is wild, and who packed it.
[*] [b]Pregnancy and fertilization[/b]: as in vanilla, only shown to players with Husbandry level 3 or higher.
[/list]
[h3]3D preview[/h3]
[list]
[*] [b]Open it[/b]: right-click a capsule and choose "Preview vehicle".
[*] [b]Controls[/b]: left-drag to rotate, right-drag to pan, scroll to zoom, double-click to reset, or use the front, side and top view buttons.
[*] [b]It shows the model, not this vehicle[/b]: the preview draws the vehicle type's default look with every optional part, not this vehicle's actual paint and parts; the list next to it shows this vehicle's real state.
[/list]
=== 🧰 Trading vehicles and animals in the Economy Center
[list]
[*] [b]Needs a recent Minidoracat Economy[/b]: a loaded capsule can be listed on the market or put up for auction, cargo included. Older Economy versions still refuse loaded capsules.
[*] [b]What buyers see[/b]: market and auction listings show the vehicle and its condition (engine and body, fuel, battery, number of missing parts, number of cargo items).
[*] [b]The buyer gets that very vehicle[/b]: the capsule they receive is the same as the original, with the same number and the same cargo; thrown, it's that vehicle, and the cargo goes back into its containers.
[*] [b]Not sold[/b]: when the seller cancels or an auction ends without a winner, the capsule comes back unchanged.
[*] [b]One capsule per listing[/b]: every capsule holds a different vehicle, so each one is its own listing; buy requests can't take them and the shop doesn't buy them.
[*] [b]When listing is refused[/b]: in the first seconds after packing, while a record is unconfirmed after a crash, or when the cargo holds something the Economy Center can't carry (for example written paper, mixed liquids, a radio with a disc inside, or more than 300 cargo items). The item picker says why; unpack, take that item out and pack again.
[*] [b]Weapon attachments[/b]: attachments come off when the capsule is listed and stay in the weapon's container, so the buyer gets the weapon and its attachments separately.
[/list]
[h3]Capsules holding an animal[/h3]
[list]
[*] [b]Listed and auctioned the same way[/b]: with a recent Minidoracat Economy, a capsule holding an animal can be listed on the market or put up for auction.
[*] [b]What buyers see[/b]: the type, the name, and the animal's kind and breed, sex, age, weight, health, milk, wool and whether it is wild; pregnancy is not shown on the listing.
[*] [b]The buyer gets that very animal[/b]: the capsule they receive has the same number; thrown, it's that animal, in the same state as when it was listed.
[*] [b]One capsule per listing[/b]: as with vehicles, buy requests can't take them and the shop doesn't buy them; listing is refused in the first seconds after packing and while a record is unconfirmed after a crash.
[*] [b]Not sold[/b]: the capsule comes back unchanged.
[/list]
=== 🧰 Performance
[list]
[*] [b]Packed vehicles are not in the world[/b]: the game spends no time on them each frame. The more vehicles you pack, and the heavier they are (KI5's vehicles, for example), the smoother things get nearby.
[*] [b]What packing can't fix[/b]: vehicles being driven and vehicles that aren't packed cost the same as before, and the moment a vehicle is unpacked may hitch briefly.
[/list]
=== ⚙️ Sandbox options and defaults
The options are on the sandbox pages "Minidoracat Universal Capsule", "Minidoracat Universal Capsule - Types" and "Minidoracat Universal Capsule - Loot"; the admin panel's "Settings", "Types" and "Loot" tabs edit these same options.
[h3]Minidoracat Universal Capsule[/h3]
[table]
[tr][th]Option[/th][th]Default[/th][th]Notes[/th][/tr]
[tr][td]Return an empty capsule after unpacking[/td][td]On[/td][td]After a capsule unpacks, an empty capsule of the same type goes back into the thrower's inventory[/td][/tr]
[tr][td]Who can pack vehicles[/td][td]Key holders[/td][td]The key in the inventory or in the ignition; can be set to "Anyone" or "Admins only"[/td][/tr]
[tr][td]Zombie attraction radius of the capsule sound[/td][td]0 tiles (0–50)[/td][td]0 means the capsule's pop attracts no zombies[/td][/tr]
[tr][td]Allow taking cargo out of capsules[/td][td]Off[/td][td]When on, players can take cargo out of a loaded capsule without unpacking the vehicle, but can't put anything in; a capsule packed in the last ~5 seconds or left unconfirmed by a crash stays locked[/td][/tr]
[tr][td]Allow packing animals[/td][td]On[/td][td]Players can pack live animals into capsules from the animal's menu; off only stops packing animals, and capsules already holding one can still be thrown, pressed and restored by admins[/td][/tr]
[tr][td]Days to keep closed records[/td][td]30 days (1–90)[/td][td]Records of capsules that were unpacked, restored or voided are deleted once their last event is older than this; packed and unconfirmed records are always kept[/td][/tr]
[/table]
[list]
[*] [b]Who can pack vehicles[/b]: admins are never limited. With Vehicle Manager installed, claimed vehicles follow it instead (the owner and players with Tow shared) and this option covers unclaimed vehicles.
[/list]
[h3]Minidoracat Universal Capsule - Types[/h3]
[table]
[tr][th]Option[/th][th]Default[/th][th]Notes[/th][/tr]
[tr][td]<Type>: can pack[/td][td]On[/td][td]Off: players can't pack vehicles with this type; loaded ones still throw or unpack with the button, and the empty capsule given back is the same type[/td][/tr]
[tr][td]<Type>: in loot[/td][td]On[/td][td]Whether this empty capsule turns up in loot; never while "can pack" is off[/td][/tr]
[/table]
[list]
[*] [b]Two per type[/b]: one pair each for Cartoon, Realistic, Dust, Steam, Sci-Fi, Magic and Shockwave.
[*] [b]Loot shared evenly[/b]: each location's weight is split over the types that are on; the total stays the same.
[/list]
[h3]Minidoracat Universal Capsule - Loot[/h3]
[table]
[tr][th]Option[/th][th]Default[/th][th]Weight[/th][/tr]
[tr][td]Empty capsules appear as loot (master switch)[/td][td]On[/td][td]—[/td][/tr]
[tr][td]Mechanic shops[/td][td]On[/td][td]0.5[/td][/tr]
[tr][td]Car supply stores[/td][td]On[/td][td]0.5[/td][/tr]
[tr][td]Gas station repair bays[/td][td]On[/td][td]0.3[/td][/tr]
[tr][td]Home garages[/td][td]Off[/td][td]0.2[/td][/tr]
[/table]
[list]
[*] [b]Master switch[/b]: when off, none of the four locations spawn empty capsules.
[*] [b]Weights[/b]: 0 to 10, on the same scale as the vanilla loot tables; higher means more often.
[*] [b]When it applies[/b]: only to containers opened for the first time afterwards; containers already searched don't refill. Changes made while the server is running apply to containers opened from then on.
[/list]
=== ⚙️ Admin panel
[list]
[*] [b]Opening it[/b]: admins see a Universal Capsule button on the family toolbar that opens "Universal Capsule Admin".
[*] [b]Hiding the button[/b]: it can be hidden in the options.
[*] [b]Who sees it[/b]: admins; regular players don't see it.
[/list]
[h3]Records[/h3]
[list]
[*] [b]Search[/b]: by capsule number or player name.
[*] [b]Filter by state[/b]: packed, unpacked, restored, voided, unconfirmed after a crash, not seen for 7 days.
[*] [b]Select a record[/b]: see its timeline (every pack, unpack, refusal, restore and verdict with time and player), its cargo list, its recorded spot and when and where the capsule was last seen.
[*] [b]Go to the recorded spot[/b]: teleports you next to the record's location, so you can check on site whether the vehicle is there.
[*] [b]Go to the last sighting[/b]: teleports you to where the server last saw the capsule (on a player, on the ground, in a container or in a vehicle). When a player says a capsule is lost, start looking there.
[*] [b]When sightings are noted[/b]: capsules on players and on the ground near them are noted all the time; one in a container or vehicle is noted when someone opens that container.
[*] [b]Not seen for 7 days[/b]: packed capsules nobody has been near for over 7 days; they may be forgotten somewhere or lost.
[*] [b]Everything is logged[/b]: every pack, unpack, refusal, restore and verdict is written to the capsule records and the server log.
[/list]
[h3]Settings, Types and Loot[/h3]
[list]
[*] [b]Settings[/b]: the general sandbox options of this mod can be changed here (return an empty capsule after unpacking, who can pack, the zombie attraction radius of the capsule sound, taking cargo out of capsules, allow packing animals, days to keep closed records); they take effect as soon as you press "Apply". Long lists scroll, and "Discard changes" and "Apply" stay at the bottom.
[*] [b]Types[/b]: one row per capsule type with its "Use" (packing) and "Loot" switches.
[*] [b]Preview[/b]: press a row's "Preview": the panel steps aside and a capsule of that type is thrown beside you, seen by you only. It works before you press "Apply" too.
[*] [b]List...[/b]: with Minidoracat Economy installed, opens a product draft for that empty capsule on the Economy Center's shop page; set the price there. A type already on sale is skipped.
[*] [b]Loot[/b]: the on/off switch and weight of each of the four locations; after "Apply", newly opened containers follow the new settings right away.
[*] [b]Permission[/b]: these are the same values as the vanilla sandbox options; changing them needs the right to change sandbox settings.
[/list]
=== ⚙️ Restoring a vehicle or an animal
[list]
[*] [b]When[/b]: the capsule is gone (lost by the player, removed by a cleanup mod, or this mod was removed and reinstalled), or a server rollback made the vehicle disappear.
[*] [b]When a player dies[/b]: the capsule stays on the body or on the ground; if it can be found, there's nothing to restore.
[/list]
[h3]How to restore[/h3]
[olist]
[*] Select the capsule in the records and use "Go to the recorded spot" first.
[*] Press "Restore vehicle". The panel steps aside and a white frame shows on the ground: that's the recorded spot (where the vehicle was last packed or unpacked).
[*] Move the mouse to where the vehicle should go: its ground turns green where it fits, red with the reason where it doesn't. Clicking the white frame restores it at the recorded spot.
[*] Left-click and confirm, and the vehicle appears there facing away from you, with its saved condition. Right-click cancels and the panel comes back.
[/olist]
Records that are unconfirmed after a crash need "I checked on site" ticked first. When you're too far from the recorded spot the white frame isn't shown, and the tooltip asks you to use "Go to the recorded spot" first.
[list]
[*] [b]Go to the recorded spot[/b]: teleports you east of the spot, two tiles clear of the vehicle's ground, so clicking the white frame right away isn't blocked by you.
[/list]
[h3]Restore rules[/h3]
[list]
[*] [b]The cargo doesn't come back[/b]: the cargo lived inside the capsule and is gone with it. The record lists the cargo types and counts; whether to hand anything out is up to the admin, and you can leave a note (for example "replaced the water bottles").
[*] [b]Never an extra vehicle[/b]: restoring makes the original capsule void at the same time, so it can't be unpacked even if it turns up later.
[*] [b]Refused if the vehicle exists[/b]: if the server can find the recorded vehicle in the world, the restore is refused.
[*] [b]Not while trading[/b]: a capsule that is listed or up for auction in the Economy Center can't be restored; the seller cancels the listing first, or the auction ends.
[*] [b]Someone else's safehouse[/b]: a restore onto a spot in someone else's safehouse is refused ("The chosen spot is in someone else's safehouse. Pick another one."); admins with the vanilla safehouse permission are exempt.
[/list]
[h3]Restoring an animal[/h3]
[list]
[*] [b]The button[/b]: for an animal capsule's record the button reads "Restore animal" and works like restoring a vehicle.
[*] [b]Landing spot[/b]: the cursor marks a single square and the white frame is the recorded spot; as when releasing an animal, water or under a vehicle won't do, and indoors is fine.
[*] [b]Written back[/b]: the animal appears with its recorded state; the time in the capsule doesn't count here either.
[*] [b]Refused if the animal exists[/b]: if the server can find that animal near its recorded spot, the restore is refused; it only finds loaded animals, so check on site before deciding.
[*] [b]Go to the recorded spot[/b]: teleports you two tiles east of the spot.
[/list]
=== ⚙️ Unconfirmed after a crash
[list]
[*] [b]How it happens[/b]: the server marks a record as saved about 5 seconds after a pack or unpack. If the server crashes within those seconds, the record shows as "Unconfirmed (crash)" after the restart.
[*] [b]What the player sees[/b]: the capsule can't be unpacked for now, and the player sees "This capsule needs an admin".
[/list]
[h3]Deciding[/h3]
Select the record, check on site, tick "I checked on site", then press:
[list]
[*] [b]Car is there, close[/b]: the vehicle is in the world. A pack record is voided (the original vehicle is still there); an unpack record stays as it is.
[*] [b]Car is gone[/b]: a pack record can be restored as usual; an unpack record goes back to packed, so the player throws the capsule again and gets both the vehicle and the cargo back. If the server can find the vehicle, "Car is gone" is refused.
[/list]
[h3]Extra cargo[/h3]
[list]
[*] [b]Confirmed saved[/b]: when a record is confirmed saved and the vehicle has been unpacked, the server clears the extra cargo out of that capsule and swaps it for an empty one.
[*] [b]Unconfirmed is left alone[/b]: unconfirmed capsules are not touched, because their cargo may be the only copy.
[/list]
[h3]Rolled-back saves[/h3]
[list]
[*] [b]Back on hold[/b]: when the server goes back to a save from before an unpack and the vehicle can't be found nearby, the record goes back to "Unconfirmed (crash)" (the timeline says "Older save, needs a check") and the capsule and its cargo are left alone.
[*] [b]The vehicle really isn't there[/b]: press "Car is gone", so the player throws the capsule again.
[*] [b]The vehicle is there[/b]: press "Car is there, close"; the extra cargo is cleared afterwards.
[/list]
=== ⚙️ Recommended setup
[list]
[*] [b]With Minidoracat Cleaner[/b]: add the seven loaded capsules (the same seven hold vehicles and animals) to its "Protected item list" sandbox option so loaded capsules on the ground are never cleaned up: [b]MinidoracatCapsule.LoadedCapsuleCartoon[/b], LoadedCapsuleReal, LoadedCapsuleDust, LoadedCapsuleSteam, LoadedCapsuleSciFi, LoadedCapsuleMagic and LoadedCapsuleShock (each with the MinidoracatCapsule. prefix).
[*] [b]Other ground-cleanup mods[/b]: please exclude these seven items there too.
[*] [b]Back it up[/b]: every capsule's record and vehicle data live in the server's [b]Zomboid/Lua/MinidoracatCapsule/[/b] folder (one subfolder per world; SP_<mode>_<save> in single player), not in the world save.
[*] [b]If that folder is deleted[/b]: packed vehicles can't be restored.
[*] [b]Back up and restore together[/b]: with the world save; if only the world save is restored, an admin has to check the already-unpacked capsules one by one.
[/list]
=== ⚠️ Known limitations
[list]
[*] [b]3D preview[/b]: draws the vehicle type's default look, not the actual paint and parts.
[*] [b]"Timed action instant"[/b]: with this admin power on, packing and pressing finish at once and a thrown capsule has no throwing animation (the capsule still flies and unpacks).
[*] [b]Can't be packed[/b]: vehicles that are towing or being towed, carry animals in a trailer, have the engine running or have someone inside.
[*] [b]Animals that can't be packed[/b]: dead, on a butcher hook, being carried, in a hutch or a trailer, or tied with a rope.
[*] [b]Throw to capture[/b]: a target that moves more than a square away from where you aimed between release and landing is missed; with both an animal and a vehicle at the spot, the animal is taken first.
[*] [b]Animal timers[/b]: time stands still in a capsule; after release the milking and petting intervals, the eggs laid that day and breeding cooldowns start over, and a wild animal's herd is not kept.
[*] [b]Animal coat (multiplayer)[/b]: vanilla lets each player's game pick the pattern, so after release different players may see different patterns.
[*] [b]Where it unpacks[/b]: vehicles not indoors (animals can be); a thrown capsule must land within about 8 tiles and in sight, and a pressed one puts the vehicle or animal within about 3 tiles of the capsule.
[*] [b]Vehicle mod removed[/b]: capsules holding its vehicles can't unpack (the tooltip says the server doesn't have this vehicle type); they work again once the vehicle mod is back.
[*] [b]Economy Center[/b]: loaded capsules can only be listed or auctioned: buy requests can't take them and the shop doesn't buy them, and a capsule whose cargo holds something the Economy Center can't carry has to be unpacked first. A recent Minidoracat Economy is needed; older versions refuse loaded capsules.
[*] [b]Capsule name[/b]: "Type: vehicle" or "Type: animal" appears once the inventory or loot window lists the capsule; Economy Center lists title it with the item's own name (for example "Steam Capsule (Loaded)") and put the vehicle or animal on the next line.
[*] [b]Restoring[/b]: brings back the vehicle, not the cargo; the server only finds vehicles that are loaded nearby, so check on site before deciding.
[*] [b]"Last seen"[/b]: only records the moment the server saw the capsule: one in a container or vehicle updates when someone opens that container, and who took it afterwards or where it went is not known.
[*] [b]After unpacking[/b]: this mod doesn't track the vehicle; use Vehicle Manager for owners and locations.
[/list]
=== ❓ FAQ
[h3]Removing this mod?[/h3]
[list]
[*] Release every vehicle and animal from its capsule first, then remove it. Capsules that are still packed disappear along with what they hold.
[*] The server records remain, so if you reinstall the mod later, admins can restore the vehicles and animals from the admin panel, but not the vehicles' cargo.
[/list]
[h3]My capsule is gone. What now?[/h3]
[list]
[*] Check bodies, the ground and the vehicle containers first.
[*] If it's really gone, give an admin the capsule number (shown in the tooltip or dialog) or your name.
[*] The admin can see where the capsule went and restore the vehicle (the cargo doesn't come back).
[/list]
[h3]What happens to capsules after a server crash?[/h3]
[list]
[*] Mostly nothing.
[*] If the crash came within a few seconds of a pack or unpack, the capsule says it needs an admin; give the number to an admin.
[*] After the admin checks on site, the vehicle and the capsule end up in the right state, with no extra vehicle and no second copy of the cargo.
[/list]
[h3]Do the records keep growing?[/h3]
[list]
[*] No. Closed records are deleted after 30 days by default (sandbox option, 1–90 days); only packed records stay for good.
[*] The number of files is fixed at 513 per world at most.
[/list]
[h3]Can I sell a loaded capsule to someone?[/h3]
[list]
[*] Yes. List it on the Economy Center market or put it up for auction: the buyer gets the same capsule (same number, same cargo), and thrown it's that vehicle.
[*] You can also drop the capsule on the ground and let them pick it up.
[/list]
[h3]Why can't I take things out of a capsule?[/h3]
[list]
[*] By design you unpack the vehicle to get them, so a crash can never create a second copy of the cargo.
[*] Servers can turn on the sandbox option "Allow taking cargo out of capsules" to let players take things out directly; a capsule waiting for an admin still stays locked.
[/list]
[h3]I can't pick up the capsule?[/h3]
[list]
[*] The cargo is too heavy. Right-click the capsule on the ground and choose "Press the Button" to unpack it right there.
[/list]
[h3]Can I pack someone else's vehicle?[/h3]
[list]
[*] A vehicle claimed in Vehicle Manager: only if the owner shared Tow with you (admins need override on).
[*] Other vehicles depend on the server: by default you need the vehicle's key, and admins always can.
[/list]
[h3]I threw it and no vehicle appeared?[/h3]
[list]
[*] The landing spot was blocked when it landed; a window shows the reason and the capsule is on the landing spot.
[*] Pick a clear spot and press the button on the ground, or pick it up and throw again.
[/list]
[h3]Is it safe in multiplayer?[/h3]
[list]
[*] Packing, unpacking and restoring are all validated by the server.
[*] The vehicle data lives only on the server, and the capsule itself only carries its name.
[/list]
[h3]Do packed animals grow or get hungry?[/h3]
[list]
[*] No. Time stands still in a capsule; the animal comes out just as it went in.
[*] The milking and petting intervals and breeding cooldowns start over.
[/list]
[h3]Does a packed wild animal become mine?[/h3]
[list]
[*] One that can be domesticated (a wild rabbit, for example) becomes tame, just like picking it up in vanilla.
[*] Animals that can't be domesticated, such as deer, stay wild.
[/list]
[h3]Why can't I pack this animal?[/h3]
[list]
[*] Hover the option and read the tooltip: the server may have "Allow packing animals" off, you may have no empty capsule, or the animal is being carried, in a hutch or a trailer, or tied with a rope.
[/list]
[h3]Why did my capsule miss?[/h3]
[list]
[*] The target moved away while the capsule was in the air (more than a square from where you aimed), or in that moment it died, was picked up, or someone got into the vehicle. The screen tells you why.
[*] The empty capsule lies on the landing spot (at your feet if that spot is in someone else's safehouse); pick it up and throw again. Aim where the animal is heading, or wait until it stops.
[/list]
[h3]Why can't I pack this in a safehouse?[/h3]
[list]
[*] It's someone else's safehouse: on a multiplayer server, vehicles and animals in someone else's safehouse can't be packed or captured, and nothing can be released there.
[*] The owner, members, staff with the vanilla safehouse permission and safehouse war time are exempt, as in vanilla; in your own safehouse you pack and release as usual.
[/list]
=== 💬 Feedback
[list]
[*] [b][url=https://github.com/Minidoracat/MinidoracatVehicleCapsuleFor42/issues]GitHub Issues[/url][/b]
[*] [b][url=https://discord.gg/Gur2V67]Discord[/url][/b]
[*] [b]Please include[/b]:
[list]
[*] your game version
[*] your mod list
[*] the vehicle or animal
[*] what happened (packing or unpacking, single player or multiplayer, and the capsule number from any dialog)
[/list]
[*] [b]Translation issues[/b]: please report them too.
[/list]
