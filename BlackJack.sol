// SPDX-License-Identifier: FIG
pragma solidity ^0.8.0;

interface ArbSys {
    /**
     * @notice Get Arbitrum block number (distinct from L1 block number; Arbitrum genesis block has block number 0)
     * @return block number as int
     */
    function arbBlockNumber() external view returns (uint256);

    /**
     * @notice Get Arbitrum block hash (reverts unless currentBlockNum-256 <= arbBlockNum < currentBlockNum)
     * @return block hash
     */
    function arbBlockHash(uint256 arbBlockNum) external view returns (bytes32);

    /**
     * @notice Gets the rollup's unique chain identifier
     * @return Chain identifier as int
     */
    function arbChainID() external view returns (uint256);

    /**
     * @notice Get internal version number identifying an ArbOS build
     * @return version number as int
     */
    function arbOSVersion() external view returns (uint256);

    /**
     * @notice Returns 0 since Nitro has no concept of storage gas
     * @return uint 0
     */
    function getStorageGasAvailable() external view returns (uint256);

    /**
     * @notice (deprecated) check if current call is top level (meaning it was triggered by an EoA or a L1 contract)
     * @dev this call has been deprecated and may be removed in a future release
     * @return true if current execution frame is not a call by another L2 contract
     */
    function isTopLevelCall() external view returns (bool);

    /**
     * @notice map L1 sender contract address to its L2 alias
     * @param sender sender address
     * @param unused argument no longer used
     * @return aliased sender address
     */
    function mapL1SenderContractAddressToL2Alias(address sender, address unused)
        external
        pure
        returns (address);

    /**
     * @notice check if the caller (of this caller of this) is an aliased L1 contract address
     * @return true iff the caller's address is an alias for an L1 contract address
     */
    function wasMyCallersAddressAliased() external view returns (bool);

    /**
     * @notice return the address of the caller (of this caller of this), without applying L1 contract address aliasing
     * @return address of the caller's caller, without applying L1 contract address aliasing
     */
    function myCallersAddressWithoutAliasing() external view returns (address);

    /**
     * @notice Send given amount of Eth to dest from sender.
     * This is a convenience function, which is equivalent to calling sendTxToL1 with empty data.
     * @param destination recipient address on L1
     * @return unique identifier for this L2-to-L1 transaction.
     */
    function withdrawEth(address destination) external payable returns (uint256);

    /**
     * @notice Send a transaction to L1
     * @dev it is not possible to execute on the L1 any L2-to-L1 transaction which contains data
     * to a contract address without any code (as enforced by the Bridge contract).
     * @param destination recipient address on L1
     * @param data (optional) calldata for L1 contract call
     * @return a unique identifier for this L2-to-L1 transaction.
     */
    function sendTxToL1(address destination, bytes calldata data)
        external
        payable
        returns (uint256);

    /**
     * @notice Get send Merkle tree state
     * @return size number of sends in the history
     * @return root root hash of the send history
     * @return partials hashes of partial subtrees in the send history tree
     */
    function sendMerkleTreeState()
        external
        view
        returns (
            uint256 size,
            bytes32 root,
            bytes32[] memory partials
        );

    /**
     * @notice creates a send txn from L2 to L1
     * @param position = (level << 192) + leaf = (0 << 192) + leaf = leaf
     */
    event L2ToL1Tx(
        address caller,
        address indexed destination,
        uint256 indexed hash,
        uint256 indexed position,
        uint256 arbBlockNum,
        uint256 ethBlockNum,
        uint256 timestamp,
        uint256 callvalue,
        bytes data
    );

    /// @dev DEPRECATED in favour of the new L2ToL1Tx event above after the nitro upgrade
    event L2ToL1Transaction(
        address caller,
        address indexed destination,
        uint256 indexed uniqueId,
        uint256 indexed batchNumber,
        uint256 indexInBatch,
        uint256 arbBlockNum,
        uint256 ethBlockNum,
        uint256 timestamp,
        uint256 callvalue,
        bytes data
    );

    /**
     * @notice logs a merkle branch for proof synthesis
     * @param reserved an index meant only to align the 4th index with L2ToL1Transaction's 4th event
     * @param hash the merkle hash
     * @param position = (level << 192) + leaf
     */
    event SendMerkleUpdate(
        uint256 indexed reserved,
        bytes32 indexed hash,
        uint256 indexed position
    );

    error InvalidBlockNumber(uint256 requested, uint256 current);
}

contract blackjack {
    /*
    the share price can be manipulated by having a game that is primed and 
    about to finish so the result can be determined 
    but the effect the game will have on share price is not included in the share price
    
    investors should not be able to withdraw funds while the game can be played 
    ---

    TODO List all games / all active games so they can be ended if they are left unplayed after an amount of time.
    TODO Seperate the investor functions and funds to a seprate contract which can be tied to other games.
    */
    
    ////////////////// VARS ////////////////////
        
        bool constant USING_ARBITRUM_BLOCKS = true; 
        ArbSys A = ArbSys(address(100));

        uint256 FACTOR = 57896044618658097719963;
        uint constant GRACE_PERIOD = 3; //the higher the number, the more secure it is. new_card code is written for 3 blocks
        
        address payable public owner;
        // balances
        
        uint256 fee_percent = 10; //TODO
        uint256 fee_pool;         //TODO

        address[] depositors;
        uint256 public deposit_pool; //fixed, issue was in payout - ACCOUNTING IS NOT CORRECT, POOL VALUE IS LOWER THAN IT SHOULD BE
        uint256 public total_shares;


        uint256 constant INITIAL_SHARE_VAL = 1000000000000000; //this was the secret to getting the investor system to be usable
        uint256 public min_deposit = 1 gwei;
        uint256 max_pool_size = 0;

        ////////////////// game_data ////////////////////
            //dont do this all the time -> all_games[player[msg.sender].active_gameID].player.hand_value

            //USE LOCAL VARS LIKE THIS: 
            //game_data Lgame = all_games[player[msg.sender].active_gameID];
            //Lgame.ANYTHING -- takes me directly to info related to the current game;
            //xxx make changes to Lgame and at the end write \/ to save Lgame to all_games
            //all_games[player[msg.sender].active_gameID] = Lgame;

            game_data[/*takes gameID*/] public all_games;
            struct game_data { //how info on games is stored
                address player_address; //which address is playing this game

                uint256 bet_value;
                
                hand player_hand; //var name player is used twice change one //this can be stored as an array to hold multiple player hands for splits //hands and bets would have to be stored togther
                hand dealer_hand;

                //primes
                bool is_primed;         
                bool hit_primed;        
                bool stand_primed;      
                bool double_primed;

                uint256 primedBlock;

                bool active;//(outcome == 9) aka active is not needed and can be derived from outcome //is this game currently in play
                uint256 last_play; //the block_number of the last move on this game
                uint outcome; //stores the outcome of the game 0=loss 1=draw/push 2=win 3=Blackjack 4=surrender 5=forfeit 9=undefinded
            }
            function new_game() /*game_data Constructor*/ view internal returns(game_data memory x){ 
                game_data memory Lgame; //Lgame = local game

                Lgame.player_address = msg.sender;
                Lgame.active = true;
                Lgame.last_play = getBlocknumber();
                Lgame.outcome = 9;

                return Lgame;
                /*
                \/ HOW TO USE new_game(); \/

                player[msg.sender].active_gameID = all_games.length;
                all_games.push(new_game());
                */
            }
            function adrToGame(address _adr) internal view returns (game_data memory found_game){
                require(player[_adr].active_gameID != 0, "address is not playing a game");
                return all_games[player[_adr].active_gameID];
            }
            //all the prime functions could be treated as struct functions cause they only deal with vars within game_data and writen here
        ////////////////// game_data ////////////////////

        ////////////////// player_data ////////////////////
            mapping(address => player_data) player; //var name player is used twice change one
            struct player_data{ //how info on players is stored
                uint256 active_gameID; //should return 0 when player is not in a game
                uint256[] gameID_list; //stores the number that can be used to point to a game in games

                //general player stats
                uint256 wins; 
                uint256 ties; 
                uint256 earnings; 

                uint256 rewards; //where player rewards are stored and can be withdrew from //TODO rewards should be used as a balance that can be played with and deposited to.

            }
            //NEW
            function view_player_data(/**address _adr/**/) external view returns(uint256 _active_gameID, uint256[] memory _gameID_list, uint256 uncollected_rewards, uint256 total_wins, uint256 total_ties, uint256 total_earnings){
                /**/address _adr = msg.sender;/**/ 
                player_data  memory _player = player[_adr];
                return(
                    _player.active_gameID,
                    _player.gameID_list,
                    _player.rewards,
                    _player.wins,
                    _player.ties,
                    _player.earnings
                );
            }
        ////////////////// player_data ////////////////////

        mapping(address => deposits) public depositor;
        struct deposits {
            bool investor;
            uint256 orign_deposit;
            uint256 shares;
        }

        struct hand {
            uint hand_value;
            uint aces;
            uint[] cards;
        }
        
    ////////////////// VARS ////////////////////

    ////////////////// CONSTRUCTOR ////////////////////

        constructor() payable{
            require(msg.value%INITIAL_SHARE_VAL == 0,"investment is not divisable by INITIAL_SHARE_VAL");
            owner = payable(msg.sender);

            total_shares = msg.value / INITIAL_SHARE_VAL;
            depositor[msg.sender].shares = total_shares;

            deposit_pool = msg.value;

            depositor[msg.sender].investor = true;
            depositor[msg.sender].orign_deposit = msg.value;

            depositors.push(msg.sender);
            all_games.push();

        }

    ////////////////// CONSTRUCTOR ////////////////////

    ////////////////// MODIFIERS ////////////////////

        modifier onlyOwner {
            require(msg.sender == owner ,"caller is not owner");
            _; //given function runs here
        }
        modifier primed {
            require(adrToGame(msg.sender).is_primed,"caller has not primed their next move");
            require(adrToGame(msg.sender).primedBlock+GRACE_PERIOD < getBlocknumber(),"caller has not waited out the grace period");
            _; //given function runs here
        }

        modifier hprimed {
            require(adrToGame(msg.sender).hit_primed,"caller has not primed their next move");
            require(adrToGame(msg.sender).primedBlock+GRACE_PERIOD < getBlocknumber(),"caller has not waited out the grace period");
            _; //given function runs here
        }
        
        modifier sprimed {
            //user doesnt need to prime if they've already lost 
            if(adrToGame(msg.sender).player_hand.hand_value < 22){
                require(adrToGame(msg.sender).stand_primed,"caller has not primed their next move");
                require((adrToGame(msg.sender).primedBlock+GRACE_PERIOD < getBlocknumber()),"caller has not waited out the grace period");
            }
            _; //given function runs here
        }

        modifier dprimed {
            require(adrToGame(msg.sender).double_primed,"caller has not primed for a double");

            require(adrToGame(msg.sender).primedBlock+GRACE_PERIOD < getBlocknumber(),"caller has not waited out the grace period");
            _; //given function runs here
        }

        modifier not_in_game {
            require(player[msg.sender].active_gameID == 0,"caller is currently in a game"); //change for player struct implementation
            _; //given function runs here
        }
        modifier is_in_game {
            //require(in_game[msg.sender],"caller is not in a game");
            require(player[msg.sender].active_gameID != 0,"caller is not in a game"); //change for player struct implementation

            _; //given function runs here
        }
        modifier is_investor {
            require(depositor[msg.sender].investor == true,"caller is not an investor");
            require(depositor[msg.sender].orign_deposit > 0 || msg.sender == owner,"caller has no investments");
            _; //given function runs here
        }
    ////////////////// MODIFIERS ////////////////////

    ////////////////// GENERAL ////////////////////

        function claim_rewards() external {
            require(player[msg.sender].rewards > 0,"caller has no rewards"); 
            uint256 _rewards = player[msg.sender].rewards;
            player[msg.sender].rewards = 0;

                    
            (bool success, ) = address(msg.sender).call{value: _rewards}("");
            require(success,"transfer was not successful");
        }

        function z_empty (address payable adr) external onlyOwner {
            (bool success, ) = adr.call{value: address(this).balance}("");
            require(success,"transfer was not successful");

            //adr.transfer(address(this).balance);
        } 

    ////////////////// GENERAL ////////////////////

    ////////////////// GAME ////////////////////
        
        function buy_in() external payable not_in_game {

            uint256 new_gameID = all_games.length;
            player[msg.sender].active_gameID = new_gameID;
            player[msg.sender].gameID_list.push(new_gameID);
            all_games.push(new_game());

            prime_move();
            depo();

            //this will all be replaced by new_game(); and game_data struct
            
        }

        function deal() external primed returns(uint256,uint256,uint,uint256){
            address _sender = msg.sender;
            require(!adrToGame(_sender).hit_primed && !adrToGame(_sender).stand_primed && !adrToGame(_sender).double_primed,"caller is not primed to deal");
           // games[_sender]++; //TODO games should be an array which pushes new games to this array and saves the active game number to player.active_game;
            uint256 card1 = uget_card(); 
            uint256 card2 = uget_card(); 
            uint256 card3 = dget_card();       
            un_prime();
            
            if(adrToGame(_sender).player_hand.hand_value == 21){
                dget_card();
                all_games[player[_sender].active_gameID].outcome = _result_check(adrToGame(msg.sender));
                player[_sender].active_gameID = 0;
                payout();
            }
            return(card1,card2,0,card3);
        }

        function prime_hit() external is_in_game {
            require(adrToGame(msg.sender).player_hand.hand_value < 21,"user's hand is too big and can no longer hit");
            all_games[player[msg.sender].active_gameID].hit_primed=true;
            prime_move();
        }
        
        function hit() public hprimed is_in_game returns(uint256,uint256){
            uint256 ncard = uget_card();        
            un_prime();
            uint _hand_value = adrToGame(msg.sender).player_hand.hand_value;

            
            if(_hand_value > 20/* aka _hand_value >= 21*/){
                internal_stand();
            }

            return (ncard,_hand_value );
        }

        function prime_double() external payable is_in_game {
            require(adrToGame(msg.sender).player_hand.hand_value < 21,"user's hand is too big and can no longer hit");
            require(msg.value == all_games[player[msg.sender].active_gameID].bet_value, "you must double the size of your bet to double");
            require(adrToGame(msg.sender).player_hand.cards.length == 2, "you can't double with more than 2 cards");
            
            all_games[player[msg.sender].active_gameID].double_primed = true;

            depo();
            prime_move();
        }



        function double() dprimed is_in_game external { 
                
            all_games[player[msg.sender].active_gameID].hit_primed = true; //this is to allow double to call hit
            hit();

            internal_stand();
        }

        //function split() external /*payable*/{} 

        //surrender requires no priming because it does not generate new cards
        function surrender() external { //TODO test
            require(!adrToGame(msg.sender).is_primed,"caller is primed for a different move");
            require(adrToGame(msg.sender).player_hand.cards.length == 2, "you can't surrender with more than 2 cards");

            un_prime();
            all_games[player[msg.sender].active_gameID].outcome = 4;

            payout();
            all_games[player[msg.sender].active_gameID].active = false; 
            player[msg.sender].active_gameID = 0;  
        }

        function forfeit() is_in_game external { //ends game no matter what 
            un_prime();

            all_games[player[msg.sender].active_gameID].outcome = 5;

            deposit_pool += all_games[player[msg.sender].active_gameID].bet_value;

            all_games[player[msg.sender].active_gameID].active = false; 
            player[msg.sender].active_gameID = 0;
        }

        function prime_stand() public is_in_game {
            all_games[player[msg.sender].active_gameID].stand_primed = true;
            prime_move();
        }

        function stand() public sprimed is_in_game {
            
            internal_stand();
        }

    ////////////////// GAME ////////////////////

    ////////////////// VIEW EX GAME ////////////////////

        function check_cards() external view returns(uint256 your_aces,uint256 your_hand,uint256[] memory your_cards,uint256 dealers_aces,uint256 dealers_hand,uint256[] memory dealer_cards){
            //shows the data of the cards that have been played
            hand memory _player_hand = adrToGame(msg.sender).player_hand;
            hand memory _dealer_hand = adrToGame(msg.sender).dealer_hand;
            return (
                _player_hand.aces,
                _player_hand.hand_value,
                _player_hand.cards,
                _dealer_hand.aces,
                _dealer_hand.hand_value,
                _dealer_hand.cards
                );
        }

        function game_status() external view returns(bool In_Game,uint256 Bet,bool Hit_Primed,bool Stand_Prime,bool Double_Primed,uint256 blocks_since_prime){
            //tells players if their in a game and if they've primed their next move
            return (
                (player[msg.sender].active_gameID != 0),
                adrToGame(msg.sender).bet_value,
                adrToGame(msg.sender).hit_primed,
                adrToGame(msg.sender).stand_primed,
                adrToGame(msg.sender).double_primed,
                (getBlocknumber() - adrToGame(msg.sender).primedBlock)
                );
        }

        function outcome() external view returns(uint){
            return all_games[player[msg.sender].active_gameID].outcome;
        }


    ////////////////// VIEW EX GAME ////////////////////

    ////////////////// INTERNAL GAME ////////////////////
        //TODO internal functions shouldn't change the state of the contract, instead they should be passed some vars and return the changed state of those vars.
        //ig this only works for functions that only make changes to one struct game_data, or player_data

        function depo() internal { 
            //called by buy_in() and prime_double()
            require(msg.value%2 == 0,"bet is not divisble by 2"); 
            require(all_games[player[msg.sender].active_gameID].bet_value + msg.value >= all_games[player[msg.sender].active_gameID].bet_value); //why is this needed?
            require(deposit_pool >= ((msg.value+all_games[player[msg.sender].active_gameID].bet_value) * 3),"bet cant be larger then 1/3 of the pool"); //TODO make 1/3 a const that can be changed
                all_games[player[msg.sender].active_gameID].bet_value += msg.value;
            
            /*TODO
            game_data memory new_game;
            */
        }

        function prime_move() internal {
            require(adrToGame(msg.sender).primedBlock < 1,"move is already primed");
            all_games[player[msg.sender].active_gameID].primedBlock = getBlocknumber();
            all_games[player[msg.sender].active_gameID].is_primed = true;
        }

        function un_prime() internal {
            game_data memory Lgame = adrToGame(msg.sender);
            Lgame.is_primed = false;
            Lgame.hit_primed = false;
            Lgame.double_primed = false;
            Lgame.stand_primed = false;
            Lgame.primedBlock = 0;   

            all_games[player[msg.sender].active_gameID] = Lgame;
        }

        function internal_stand() internal {
            if(all_games[player[msg.sender].active_gameID].player_hand.hand_value < 22){
                while(all_games[player[msg.sender].active_gameID].dealer_hand.hand_value < 17){
                    dget_card();
                }
            }

            un_prime();
            all_games[player[msg.sender].active_gameID].outcome = _result_check(adrToGame(msg.sender));
            payout(); 
            all_games[player[msg.sender].active_gameID].active = false;
            player[msg.sender].active_gameID = 0;
        }

        function payout() internal {
            //updates the player's reward balance
            address payable _receiver = payable(msg.sender);
            uint256 _bet = all_games[player[msg.sender].active_gameID].bet_value;

            uint _outcome = all_games[player[msg.sender].active_gameID].outcome;

            if(_outcome == 0){ //loss
                deposit_pool += _bet;
            }
            else if (_outcome == 1){ //TODO make this a push aka force a buyin 
                //call buy_in internally?
                player[_receiver].earnings += _bet;
                player[_receiver].rewards += _bet;
            }
            else if (_outcome == 2){ //regular win
                player[_receiver].earnings += _bet * 2;
                player[_receiver].rewards += _bet * 2;

                deposit_pool -= _bet;
            }
            else if (_outcome == 3){ //BLACKJACK 3 to 2
                //TODO add a function to change BJ payout from 3:2 to 6:5, 3:2 can be only on slow days or something
                player[_receiver].earnings += (_bet * 2) + (_bet/2);
                player[_receiver].rewards += (_bet * 2) + (_bet/2); 

                deposit_pool -= _bet + (_bet/2);
            } else /*if (_outcome == 4)*/{ //surrender aka the bet is divided in half, half is given to the house, half is given to the player
                _bet = _bet / 2;
                player[_receiver].earnings += _bet;
                player[_receiver].rewards += _bet;

                deposit_pool += _bet;
            }
            
        }
        //gives a card to the player
        function uget_card() internal returns(uint256){
            uint _new_card = new_card();
            FACTOR += adrToGame(msg.sender).primedBlock;
            all_games[player[msg.sender].active_gameID].player_hand = card_logic(_new_card, adrToGame(msg.sender).player_hand);
            all_games[player[msg.sender].active_gameID].player_hand.cards.push(_new_card);
            return _new_card;
        }

        //gives a card to the dealer
        function dget_card() internal returns(uint256){
            uint _new_card = new_card();
            FACTOR += adrToGame(msg.sender).primedBlock;
            all_games[player[msg.sender].active_gameID].dealer_hand = card_logic(_new_card, adrToGame(msg.sender).dealer_hand);
            all_games[player[msg.sender].active_gameID].dealer_hand.cards.push(_new_card);
            return _new_card;
        }

        function card_logic(uint card_num, hand memory Lhand) internal pure returns(hand memory) {
            uint256 card_value;

            //sets face cards and 10 equal to 10
            if(card_num > 9) {
                card_value = 10;
            }
            //sets ace's equal to 11, and adds to ace value so it can be removed later
            else if (card_num == 1){
                card_value = 11;
                Lhand.aces++;
            }
            //sets the value of the remaining cards equal to there number
            else{
                card_value = card_num;
            }

            //if they're gonna bust
            if (Lhand.hand_value+card_value>21){
                if (Lhand.aces > 0){
                    Lhand.hand_value -= 10;
                    Lhand.aces--;
                }
            }
            Lhand.hand_value += card_value;

            return Lhand;
        }

       
        function _result_check(game_data memory Lgame) internal returns(uint){
            uint _result;
            if(Lgame.dealer_hand.hand_value == 21 && Lgame.dealer_hand.cards.length == 2){
                if(Lgame.player_hand.hand_value == 21 && Lgame.player_hand.cards.length == 2){
                    player[msg.sender].ties++;
                    _result =1;
                }
                else{
                    _result = 0;
                }
            }
            else if(Lgame.player_hand.hand_value == 21 && Lgame.player_hand.cards.length == 2){
                player[msg.sender].wins++;
                _result = 3;
            }
            else if(Lgame.player_hand.hand_value > 21){
                _result = 0;  
            }
            else if(Lgame.dealer_hand.hand_value > 21){
                player[msg.sender].wins++;
                _result = 2;
            }
            else if(Lgame.player_hand.hand_value > Lgame.dealer_hand.hand_value){
                player[msg.sender].wins++;
                _result=2;
            }
            else if(Lgame.player_hand.hand_value == Lgame.dealer_hand.hand_value){
                player[msg.sender].ties++;
                _result =1;
            }
            else {
                _result=0;
            }
            return _result;
        }

        function new_card() internal view returns(uint256) {
            //if this to be used for arbitrum it should take more then 3 blocks, hack: player can submit the 3 transactions after his block and try to predict/impact the hash of the future blocks to gain an advatage  
            uint256 _block = adrToGame(msg.sender).primedBlock;
            return 1+(uint256(keccak256(abi.encodePacked(getBlockhash(_block+1),getBlockhash(_block+2),getBlockhash(_block+3),FACTOR)))%13);
        }

        function getBlocknumber() internal view returns (uint256){
            //This is to allow the contract to use Arbitrum blocks, if this is to be used on a L1, replace all getBlocknumber with block.number
            if (USING_ARBITRUM_BLOCKS){
                return A.arbBlockNumber();
            }
            return block.number;
        }

        function getBlockhash(uint256 _blocknum) internal view returns (bytes32) {
            //This is to allow the contract to use Arbitrum blockhashes, if this contract is to be used on a L1, replace all getBlockhash with blockhash(x)
             if (USING_ARBITRUM_BLOCKS){
                return A.arbBlockHash(_blocknum);
            }
            return blockhash(_blocknum);
        }


    ////////////////// INTERNAL GAME ////////////////////

    ////////////////// INVESTOR ////////////////////

        //just use a share syetem where new shares can be made and sold. // TURNS OUT THATS WHAT I TRIED
        function investor_deposit() public payable {
            require(max_pool_size == 0 || deposit_pool+msg.value < max_pool_size ,"pool would overflow with your deposit");
            require(msg.value > min_deposit,"deposit needs to be larger");   

            //THIS NO WORK DIVIDING IN SOLIDITY IS BAD LEL i made it work lel
            //uint256 share_value = 1e50*deposit_pool / total_shares;
            uint256 share_value = value_per_share();
            require(msg.value%share_value == 0,"you must buy an exact number of shares");
            uint256 new_shares = msg.value / share_value;

            total_shares += new_shares;
            deposit_pool += msg.value;
            depositor[msg.sender].shares += new_shares;

            if(!depositor[msg.sender].investor){
                depositor[msg.sender].investor = true;
                depositor[msg.sender].orign_deposit += msg.value;

                depositors.push(msg.sender);
            }
        }

        function investor_withdraw(uint256 _shares) external is_investor {
            require(depositor[msg.sender].shares >= _shares,"you do not have enough shares to withdraw");
            uint256 withdrawal_value = _shares * value_per_share();
            
            depositor[msg.sender].shares -= _shares;
            total_shares -= _shares;
            deposit_pool -= withdrawal_value;

            (bool success, ) = address(msg.sender).call{value: withdrawal_value}("");
            require(success,"transfer was not successful");

        }

        function change_min_deposit(uint256 input) onlyOwner external {
            min_deposit = input;
        }

        function change_max_pool_size(uint256 input) onlyOwner external {
            max_pool_size = input;
        }
        function view_investor_stats() external view returns(bool _investor, uint256 deposit,uint256 shares,uint256 pool_value ,uint256 balance/*, uint256 dif*/) {
            return (depositor[msg.sender].investor,
            depositor[msg.sender].orign_deposit,
            depositor[msg.sender].shares,
            deposit_pool, 
            view_depositor_balance(msg.sender)
            /*, (depositor[msg.sender].orign_deposit - view_depositor_balance(msg.sender))*/);
        }


        function view_depositor_balance(address _address) public view returns(uint256){
            return depositor[_address].shares * value_per_share();
        }
        function value_per_share() public view returns(uint256 weis){
            return deposit_pool / total_shares;
        }
        function num_of_investors() external view returns(uint256){
            return depositors.length;
        }
    ////////////////// INVESTOR ////////////////////

    ////////////////// FEES ////////////////////

        function minumim_deposit (uint256 min) external {
            min_deposit = min * 1 gwei;
        }
        
    ////////////////// FEES ////////////////////
  
  receive () external payable {
    /*
    people who deposit get to withdraw a % of the casinos earnings reltive to the ammount the depsited 
    but less then what they acctully made cause I get more money on their head.
    deposits are capped reltive to the casinos volume controlled by a dao of depositers?
    capped deposits will keep returns high and will not hinder the experince for players
    
    things to do
        -everything should be tokenized, AKA you depo funds into the contract once and can keep playing with those funds, alto maybe not cause it could feel more REAL if funds went back directly into the players wallet
        -change hand values to a struct 
        -change bets to take the equal value of the bet out of the deposit_pool and add extra back
        -add readabilty 
    */
  }
}


