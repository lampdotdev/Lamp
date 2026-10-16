import Foundation

/// The words a ladder may step through: common four-letter English words, kept family-friendly. A word that isn't
/// here is refused, so a missing everyday word reads as a bug; add it to the list below (any order, spaces
/// between words) and every puzzle's par still holds, since a new word can only make a path shorter, never break
/// one. Taking a word out can lengthen a puzzle's shortest path, so check `WordLadder.pairs` after removing any.
enum Words {
    static let all: Set<String> = Set(list.split(whereSeparator: \.isWhitespace).map(String.init))

    private static let list = """
    able ache acid acne acre acts aged ages aide aids aims airs airy ajar also alto alum amid amps ants apes apex
    aqua arch arcs area aria arid arms army arts ashy atom aunt aura auto avid away awed axes axis axle
    baby back bade bags bail bait bake bald bale ball balm band bang bank bans barb bard bare bark barn bars base
    bash bask bass bath bats bays bead beak beam bean bear beat beds beef been beep beer bees beet bell belt bend
    bent best beta bets bias bibs bide bike bill bind bird bite bits blew blob blog blot blow blue blur boar boat
    bobs body boil bold bolt bond bone bony book boom boon boot bore born boss both bout bowl bows boys brag bran
    brew brim brow buck buds buff bugs bulb bulk bull bump bunk buns buoy burn burp burr bury bush bust busy buys
    buzz byte
    cabs cafe cage cake calf call calm came camp cane cans cape caps card care carp cars cart case cash cask cast
    cats cave cell cent chap chat chef chew chin chip chop chow cite city clad clam clan clap claw clay clip clod
    clog clot club clue coal coat coax code coil coin cola cold colt comb come cone cook cool coop cope copy cord
    core cork corn cost cosy cots coup cove cows cozy crab crew crib crop crow cube cubs cued cues cuff cull cult
    cups curb curd cure curl curt cute cuts
    dabs dads daft dais dale dame damp dams dare dark darn dart dash data date dawn days daze dead deaf deal dean
    dear debt deck deed deem deep deer dens dent desk dial dice died dies diet digs dill dime dine ding dips dire
    dirt disc dish disk dive dock does dogs dole doll dome done doom door dose dote dots dove down doze dozy drab
    drag draw drew drip drop drum dual duck duct dude duel dues duet dull duly dumb dump dune dunk dusk dust duty
    dyed dyes
    each earl earn ears ease east easy eats echo edge edgy edit eggs else emit ends envy epic even ever evil exam
    exit eyed eyes
    face fact fade fads fail fair fake fall fame fang fans fare farm fast fate fawn fear feat feed feel fees feet
    fell felt fend fern fest feud fiat fibs figs file fill film find fine fins fire firm fish fist fits five fizz
    flag flak flap flat flaw flax flea fled flee flew flex flip flit flog flop flow flue flux foal foam foes fogs
    foil fold folk fond font food fool foot ford fore fork form fort foul four fowl foxy fray free fret frog from
    fuel full fume fumy fund funk furl fury fuse fuss fuzz
    gain gait gala gale gall game gang gaps garb gash gasp gate gave gaze gear geek gels gems gene gift gild gill
    gilt girl gist give glad glee glen glib glow glue glum gnat gnaw goal goat gods goes gold golf gone gong good
    goof goon gore gosh gown grab gram gray grew grey grid grim grin grip grit grow grub gulf gull gulp gums gush
    gust guts guys gyms
    hack hail hair hale half hall halo halt hams hand hang hard hare harm harp hash hate hats haul have hawk haze
    hazy head heal heap hear heat heed heel heir held helm help hems hens herb herd here hero hers hide high hike
    hill hilt hind hint hips hire hiss hits hive hoax hold hole holy home hood hoof hook hoop hoot hope hops horn
    hose host hour howl hubs huge hugs hula hulk hull hump hums hung hunk hunt hurl hurt hush husk huts hymn
    iced ices icky icon idea idle idly idol inch info into iron isle itch item
    jabs jack jade jags jail jams jars jaws jays jazz jeep jeer jell jerk jest jets jobs jogs join joke jolt jots
    joys judo jugs jump june junk jury just jute
    keel keen keep kegs kelp kept keys kick kids kiln kilt kind king kink kiss kite kits kiwi knee knew knit knob
    knot know
    labs lace lack lacy lads lady laid lain lair lake lamb lame lamp land lane laps lard lark lash lass last late
    lava lawn laws lays lazy lead leaf leak lean leap left legs lend lens lent less lest levy liar lice lick lids
    lied lies life lift like lily limb lime limp line link lint lion lips lisp list live load loaf loan lobe lock
    loft logo logs lone long look loom loop loot lord lore lose loss lost lots loud lout love lows luck lull lump
    lung lure lurk lush lute
    mace made maid mail main make male mall malt mane many maps mare mark mars mash mask mass mast mate math maze
    mead meal mean meat meek meet meld melt memo mend menu meow mere mesh mess mice mild mile milk mill mime mind
    mine mint mist mite mitt moan moat mobs mock mode mold mole molt monk mood moon moor moot mope mops more moss
    most moth move mows much muck muds mugs mule mull muse mush musk must mute mutt myth
    nags nail name nape naps navy near neat neck need nerd nest nets news newt next nice nick nine node nods none
    nook noon norm nose nosy note noun nuts
    oafs oaks oars oath oats obey odds odor offs ogre oils oily okay omen omit once ones only onto ooze opal open
    opts oral orbs ouch ours oust outs oval oven over owed owes owls owns
    pace pack pact pads page paid pail pain pair pale palm pals pane pang pans pant pare park part pass past path
    pats pave pawn paws pays peak peal pear peas peat peck peek peel peep peer pegs pelt pens pent perk pest pets
    pick pier pies pigs pike pile pill pine ping pink pins pint pipe pits pity plan play plea pled plod plop plot
    plow ploy plug plum plus pods poem poet poke pole poll polo pond pony pool poor pops pore pork port pose posh
    post pots pour pout pray prep prey prim prod prom prop pros prow puck puff pull pulp puma pump punk puns pups
    pure purr push puts putt
    quay quit quiz
    race rack raft rage rags raid rail rain rake ramp rams rang rank rant rare rash rasp rate rats rave rays raze
    read real ream reap rear reed reef reek reel rein rely rent rest ribs rice rich ride rife rift rigs rile rims
    rind ring rink riot ripe rise risk rite road roam roar robe robs rock rode rods role roll romp roof room root
    rope rose rosy rots rove rows rubs ruby rude rugs ruin rule rump rune rung runs runt ruse rush rust
    sack safe saga sage said sail sake sale salt same sand sane sang sank saps sash sass save saws says scab scam
    scan scar seal seam sear seas seat sect seed seek seem seen seep seer sees self sell semi send sent sets sewn
    shed shin ship shoe shoo shop shot show shut sick side sift sigh sign silk sill silo silt sing sink sips sire
    site sits size skid skim skin skip skis slab slam slap slat sled slew slid slim slip slit slob slot slow slug
    slum slur smog snag snap snip snob snow snub snug soak soap soar sobs sock soda sofa soft soil sold sole solo
    some song sons soon soot sore sort soul soup sour sown sows soya span spar spat spec sped spin spit spot spry
    spud spun spur stab stag star stay stem step stew stir stop stow stub stud stun such suds suit sulk sums sung
    sunk suns sure surf swam swan swap sway swim
    tabs tack taco tact tags tail take tale talk tall tame tang tank tans tape taps tarp tart task taxi teal team
    tear teas teem teen tell temp tend tens tent term tern test text than that thaw them then they thin this thud
    thug thus tick tide tidy tied tier ties tile till tilt time tint tiny tips tire toad toed toes tofu toga toil
    told toll tomb tome tone tons took tool toot tops tore torn toss tote tour tout town toys tram trap tray tree
    trek trim trio trip trod trot true tuba tube tubs tuck tuft tugs tuna tune turf turn tusk tutu twig twin twos
    type
    ugly undo unit unto upon urge used user uses
    vain vale vane vary vase vast vats veal veer veil vein vent verb very vest veto vets vial vibe vice view vile
    vine visa void vole volt vote vows
    wade wads waft wage wags waif wail wait wake walk wall wand wane want ward ware warm warn warp wars wart wary
    wash wasp watt wave wavy waxy ways weak wear webs weed week weep weld well welt went wept were west wets what
    when whim whip whir whiz wick wide wife wigs wild will wilt wily wimp wind wine wing wink wins wipe wire wise
    wish wisp with wits woke wolf wont wood wool word wore work worm worn wove wrap wren writ
    yank yaps yard yarn yawn yeah year yell yelp yoga yoke yolk your yowl
    zany zaps zeal zero zest zinc zing zips zone zoom zoos
    """
}
