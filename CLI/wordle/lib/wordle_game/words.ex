defmodule WordleGame.Words do
  @moduledoc """
  Wordle 게임용 5글자 단어 목록
  """

  @words ~w(
    about above abuse actor acute admit adopt adult after again agent agree
    ahead alarm album alert alien align alike alive allow alloy alone alpha
    alter amaze amber amend ample angel anger angle angry ankle apart apple
    apply arena argue arise armor aroma arose array arrow aside asset audio
    audit avoid awake award aware awful bacon badge badly baker basic basin
    basis batch beach beard beast began begin begun being belly below bench
    berry birth black blade blame blank blast blaze bleed blend bless blind
    block blond blood bloom blown blues blunt board boast bonus boost booth
    born bound boxer brain brake brand brave bread break breed brick bride
    brief bring broad broke brown brush buddy build built bunch burst buyer
    cable cache camel canal candy cargo carry carve catch cause cease chain
    chair chaos charm chart chase cheap check cheek chest child chill china
    chips chord chose chunk claim class clean clear clerk click cliff climb
    cling clock close cloth cloud coach coast color colon combo comic coral
    couch could count court cover crack craft crane crash crawl crazy cream
    creek crime crisp cross crowd crown crude crush curve cycle daddy daily
    dairy dance dated dealt death debug decay decor decoy delay delta dense
    depot depth dirty disco ditch diver dizzy dodge donor doubt dough draft
    drain drama drank drawer drawn dream dress dried drift drill drink drive
    drone drown drunk dryer dunno dusty dwell dying eager eagle early earth
    eaten edge eight elder elect elite email embed ember empty enemy enjoy
    enter entry equal equip error essay ethics evade even event every exact
    exert exile exist extra faint fairy faith false fancy fatal fatty fault
    favor feast fiber field fifth fifty fight final first fixed flame flash
    fleet flesh float flock flood floor flour fluid flush focal focus foggy
    force forge forth forty forum fossil found frame frank fraud freak fresh
    front frost fruit fully funny fuzzy ghost giant given glass gleam globe
    glory glove gotta grace grade grain grand grant grape grasp grass grave
    great greed greek green greet grief grill grind groan gross group grove
    grown guard guess guest guide guild guilt habit hairs hairy handy happy
    harsh haste hasty hatch haven heart heavy hedge hello hence herbs hired
    hobby hockey holly honey honor horse hotel hound house hover human humid
    humor hurry hyper ideal image imply inbox incur index indie infer inner
    input inter intro ionic irate irish issue items ivory jelly jewel joint
    joker jolly judge juice jumbo jumpy junior juror karma kayak kebab keeps
    ketch khaki kicks kiddo kills kinda kinds kings kinky kiosk kiss kites
    kitty knack knead kneel knelt knife knobs knock knots known label labor
    laden ladle lands lanes laptop large laser latch later laugh layer leads
    leafy learn lease least leave ledge legal lemon level lever light liked
    limbs limit lined linen liner lines lingo links lions lists liter lived
    liver lives loads loans lobby local lodge logic login lonely longs looks
    loops loose lorry loser lotus loud lousy loved lover loves lower loyal
    lucid lucky lunar lunch lunge lying lyric macho macro madam magic magma
    major maker males malls manga mango mania manor maple march marco maria
    marks marsh masks mason masse match mates maths matrix maxim mayor meals
    means meant meats medal media melee melon mercy merge merit merry messy
    metal meter midst midst might mimic minds miner minor minus misty mixed
    mixer model modem modes moist money month moose moral moses motor motto
    mould mount mouse mouth moved mover moves movie mucus muddy mummy mural
    music naive named nasty naval needs nerve never newer newly nicer niche
    night ninja ninth noble noddy nodes noise noisy norms north notch noted
    notes novel nurse oasis occur ocean oddly odds offer often olive omega
    onset opens opera optic orbit order organ other ought outer outgo owned
    owner oxide ozone pablo packs pagan pages pains paint pairs panel panic
    pants papal paper paris parks parry parse party pasta paste patch patio
    pause peace peach pearl pedal peers penal penny perch peril perks pesto
    petty phase phone photo piano picks piece piggy pilot pinch pipes pitch
    pizza place plain plane plans plant plate plaza plead pleas plier pluck
    plumb plump plums poems poets point polar poles polls ponds pools porch
    porno posed poses posse posts pouch pound power press price pride prime
    print prior prism prize probe promo prone proof prose proud prove proxy
    prune psalm pubic pulse pumps punch pupil puppy purge purse pussy queen
    query quest queue quick quiet quilt quirk quite quota quote radar radii
    radio rails rainy raise rally ranch range ranks rapid rated rates ratio
    razor reach react reads ready realm rebel recap refer reign relax relay
    remit remix renal renew repay reply rerun reset resin retro rider rides
    ridge rifle right rigid rinse riots ripen risen rises risks risky rites
    ritzy rival river roast robot rocky roger rogue roles roman roofs rooms
    roots ropes roses rouge rough round route rover royal rugby ruins ruler
    rules rumors rural rusty sadly safer sails saint salad sales salon salsa
    salty sandy satin sauce sauna saved saver saves scale scalp scams scant
    scare scarf scary scene scent scoop scope score scout scrap screw seals
    seams seats seeds seeks seems seize sells sends sense serum serve setup
    seven sever shade shady shaft shake shall shame shape shard share shark
    sharp shave sheet shelf shell shift shine shiny ships shirt shock shoes
    shook shoot shops shore short shots shout shown shows shrug sides siege
    sight sigma signs silky silly since siren sites sixth sixty sized sizes
    skate skies skill skirt skull slabs slack slain slang slant slash slate
    slave sleek sleep slept slice slide slime slimy sling slots slump slush
    small smart smash smell smile smoke smoky snack snake snaps sneak sniff
    snort snowy sober social socks sodium soils solar solid solve sonar songs
    sonic sorry sorts sough souls sound soup south space spade spain spare
    spark spasm spawn speak spear specs speed spell spend spent spice spicy
    spied spies spike spill spine spirit spite split spoil spoke spoon sport
    spots spray spree spurs squad stack staff stage stain stair stake stall
    stamp stand stare stark stars start stash state stays steak steal steam
    steel steep steer stems steps stern stick stiff still sting stink stock
    stole stomp stone stood stool stoop stops store storm story stout stove
    strap straw stray strep strip strut stuck study stuff stung stunk style
    suave sugar suite suits sunny super surge sushi swamp swans swaps swarm
    swear sweat sweep sweet swept swift swine swing swipe swiss sword swore
    sworn swung synod syrup table tacit tacos tails taken takes tales talks
    tally tanks tapes tardy tasks taste tasty taxes teach teams tears tease
    teddy teens teeth tempo tends tenor tense tenth terms terra terry tests
    texts thank theft their theme there these thick thief thigh thing think
    third thong thorn those three threw thrill throb throw thumb thump tiger
    tight tiles timer times timid tired titan title toast today token tones
    tonic tools tooth topic torch total touch tough tours towel tower towns
    toxic trace track tract trade trail train trait tramp trans trash trawl
    treat trees trend trial tribe trick tried tries trike trillion trims trips
    troop trout truce truck truly trump trunk trust truth tumor tuned tunes
    turbo turns tutor tweak tweed tweet twice twigs twine twins twirl twist
    ultra uncle under undid undue unfair unify union unite units unity unknown
    until upper upset urban urged urine usage users using usual utter vague
    valid value valve vapor vault vegan veins velvet venue verse very vessel
    video views villa vines vinyl viola viral virus visit vista vital vivid
    vocal vodka vogue voice volts vomit voted voter votes vouch vowel wages
    wagon waist walks walls waltz wanna wants warns warts wasps waste watch
    water watts waves waxed weary weave wedge weeds weeks weigh weird wells
    welsh wetly whale wharf wheat wheel where which whiff while whine whips
    white whole whomp whose wicked wider widow width wield wilds wills winds
    wines wings wiped wiper wipes wired wires witch witty wives wizard woken
    woman women woods woody words wordy works world worms worry worse worst
    worth would wound woven wrack wraps wrath wreck wrest wring wrist write
    wrong wrote yacht yards yarn yawns years yeast yield young yours youth
    zebra zesty zilch zones zooms
  )

  @doc """
  랜덤 5글자 단어를 반환합니다.
  """
  def random_word do
    Enum.random(@words)
  end

  @doc """
  단어가 유효한지 확인합니다. (5글자 알파벳)
  """
  def valid_word?(word) when is_binary(word) do
    word = String.downcase(word)
    String.length(word) == 5 and String.match?(word, ~r/^[a-z]+$/)
  end

  def valid_word?(_), do: false

  @doc """
  단어가 목록에 있는지 확인합니다.
  """
  def in_word_list?(word) do
    String.downcase(word) in @words
  end
end
