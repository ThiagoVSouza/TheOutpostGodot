
# Overall Game App characteristics

- The game is comprised of one core layer containing the base application in godot, ai models, overall game configuration and assets.
    - The core game also contains the main screens and also common core logic
    - It will also contain a core data (game lore, overall world rules, core definitions, etc)
    - Free content updates will reside in the core module and will be promptly available to any DLC/module.


- It also contains a list of DLC / modules that a player may have purchased.
    - Each DLC is Game play mode or angle of playing the game, for example next one will be "Adventure Company", which instead of controlling a domain, you will be managing a party. It will have different logic but will share all core foundations (it may or may not have exclusive screens)
    - The game ships from day 1 with at least one DLC/Module which is "The Outpost" 
    - Each dlc/module has its own assets (images, sounds, workflows, memories, configurations)
    
- We may in the future move into creating separated games from the DLC. Ie: we keep the core module but the first module that comes with it is the "Adventure Company" and the user may buy "the outpost" as a dlc for this game. (This is just a possibility as I dont think anyone tried this before as far as I know - but in any case we cant, at least keep it as the outpost as main game and others as dlcs)

- Besides DLcs we will eventually release free content update. This can inlcude new assets, evetns, and even game rules/screens

# Core game Flow

1. Splash screen shows with Company Logo (I am leaning on changing this to Pangea Games from NTX Games)

2. A loading screen shows (just a background image with a bottom progress bar).
    - In this step every asset that needs to be loaded to render the main Menu (all images, AI model (?), sounds/music, configurations, etc )
    - In this loading phase we may have a check for updated versions or content. (Some content like new DSL may not require updating the app itself and just some new content like assets, dsl, data, lore, etc) (We will try to use main stores way of delivering this rather than creating our own distribution backend/cdn)
    - Main settings are loaded and applied 

3. Main menu has option to continue last game, new game, load game and settings, help, news, some social media links and account. 

# How a new game should flow:

1. USer clicks in the new game main menu item.
    - App should check list of DLCS available.

2. A screen containing option to pick game mode/dlc to play. In case the user only have one game this screen may be skipped and go to next point.

3. Once the game/dlc is chosen the app should check the configuration of this module.
    - In this configuration there should be an initialization flow/configuration which will show what will be in the game "new game wizard".
    - The app should transition to a loading screen loading all assets necessary to show the wizard only.
    - The wizard screen is displayed and all the steps are composed as in the configuration.

4. Once the user finishs the wizard and in the final button clicks start then the game will transition to a loading screen
    - IN this screen first it will load all the assets necessary to run the game per se:
        - The core Game assets necessary to start the game are loaded to memory
        - Current game files/folder is emptied from any previous content (Also all cache is cleared if any exists)
        - Current Game memory and JSON files are created empty
        - Game Map and main screens/engine is loaded
        - A new current game map file is created. 
    - THen the new game workflow is run:
        - this workflow will receive the parameters picked in the initialization wizard (ie: what is the hero name, what is the background, flag colors and emblem chosen, and any other configuration)
        - This workflow will right away modify a few things, for example will set a few game states (outpost location on map, how much gold, hero character is created), will add some memories based on the choices, etc.
    - Then it will start a new workflow that will set the current game: ie in the outpost it will start a new event where the chat is opened a dynamic image is shown on top with the throne room and then it will start with the king granting the outpost and giving instructions and letting the user do his first chat interation with the king and or the game itself.

    - This start workflow will also start the main game quest (and maybe some sub quests). This is different from hard coded linear quests from standard games. 
        - For example the main quest is a Kings order to take over the outpost and solidify it in 5 years.
            - This will be assessed in 5 years, so there is an event that needs to trigger in 5 years for checking this.
            - The assessment will be done by the Kings Steward. This assessment may be based on his personal interests and/or disposition towards the player´s hero.
    * I will explain how plans and memories work below.

# What A current running game will have

Here are some overall game flows that are important for how we structure memory/workflows, lore, etc.

1. Main & side quests

The main quest in the Outpost will be the consolidation of the outpost, first it is to consolidate and estabilish a secure and stable outpots, then expading it to a setlement and then finally make it into a formal province.

This main quest will need to be flexible, like what if the user do not achieve stage 1? It will need to be reassed again or the king may just fire the PLayer and the Game is over if he accepts.
PLayer may choose to ignore and rebel against the king, maybe seek independence so steering the main quest in na new direction or even ending it.

The main quest might have attached sub quests. For example the steward is responsible to assessing the progress for the King. There could be a sub plot going on where the steward is corrupt. This needs to be factored and maybe a plan on itself trackign intentions, facts that have happened and maybe a master direction where this event is going (like is the steward trying to extort the player? did they antagonize each other and he is trying a payback like hiring some mercenaries to atack the player outpost? etc...)

The religous head of the state church may be angry at the outpost and influence the King´s decision on how the outpost is going and its promotion and funding. 

2. Events

Each event can be simple or very complex with multiple steps.
For example it can be: a wolf killed some sheeps in a farm. And it generates a memory tracking this and the location where the wolf is. And the user may or may not act on it.
This may trigger peasents trying to kill the beast or asking the player to solve this issue.
Player may ignore the event copmletely (And maybe suffere consequences).
Some evnts can be multiple steps, like: bandits planned to rob region and roads. This may trigger events when someone passes there, may include the creation of a hideout base.
There could also be some situation brewing, like some peasents are planning a revolt. They may have several options like sabotage, corruption, killings, etc. And X ammount of time the event will be retriggered to see if something else should happen baased on the level of unhappines. The player may intervene and based on the intervention the event may mutate (end conflict, escalate it, consiliate, etc). This mutations happen on memory level and planning level.

3. Character Intentions

Character will have intentions and plans associated with their history, personality and events happening.
For example A captain in the guard may be plotting a coup in the outpost.
Or a merchant is seeking to stabilish a new trade route.
A character may be content and not aiming anything , or be ambicious and looking to increase his position or his house´s.
A tribal leader may be seeking revenge agains another enemy tribe. 

4. Nations/Group directions

There can also be cases where inanimate things may have plans and directions.
For example a neighbor tribe may be willing to increase the relatioship with the outpost.
A group of bandits may be looking for things to loot. Or might have been hired to attack the outpost (they may fullfill or not it and might think on how to proceed).

5. Combat

Military action will also be very interesting for this. THe player may send a team of hunters to kill a pack of wolves. HE may give directions but in the situation it may react and mutate, maybe they find other things and have to handle it.

General combat can be also complex like player give orders to man the wall with archers, and this order needs to be tracked. 

He may also order a captain to take some soldiers and attack a neighbor tribe. He may give specific orders and these need to be tracked. Maybe the captain will not follow or ignore the orders. He may adjust to ground events, etc.

===

# Plans, Memories & Orchestration 

1. I believe we need to track "things" happening via plans. Plans can be linked to events, characters, locations, and anything else.
They can be just plain files (or db entries) listing events that happened, goals, what is going on, etc.
Ai will read this in context to judge and decide what is going on, next steps, which tools to call to trigger new associated events, create new workflows, update memories, etc.

2. Plans can be running outside player scope, like something is happening in the capital unrelated to him. This will be a background plan/event/intention.


===

# Data

As we have different interaction with AI in our workflow system we need a different system of data.

1. One example is an multi step indexed system.
- For example in an orchestration needs  to find all information relevant to make a decision.
- This information should be sent to ai as context for it to judge the next step, difficulty, any action to be taken, an event to be fired, creation of a new workflow, etc.
- For example it can have an index containing the keys and what they represent. Orchestration will feed a list of this first index and then AI will say: fetch all secondary indexes for A and C. Then the tool fetchs sub indexes for A and C and feed again to ai and AI will then say: now give me all data regarding subindexed A1,A3, and C5.
Then this data will be used to create the final context for A prompt that will update memory, plans, or even be used to create a new workflow.

2. Alternatively we can have an sqlite for fast searching instead of multiple json files. Maybe add several columns as indexes and maybe one table explaining what each index can contain. and this is fed to AI.

===

# Final goal

The plan is very unusual and is aiming very high. This is probably a task never attempt before in gaming. But I feel it is achievable if we mix can mix the right Ai,Orchestration, Memories, game rukes and game structure.

We need to ensure it is open and flexible enough on how to do this. It will most likely lots of testing and modifications. If the "Lego" blocks are in place this step will be theone remaining and I expect it to be more on me and manual (And also with beta testing with users).
