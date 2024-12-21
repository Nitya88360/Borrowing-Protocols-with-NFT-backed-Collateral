// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract NFTCollateralBorrowing is ReentrancyGuard {
    using Counters for Counters.Counter;

    struct Loan {
        address borrower;
        address lender;
        uint256 nftId;
        address nftContract;
        uint256 loanAmount;
        uint256 interestRate;
        uint256 duration;
        uint256 startTime;
        bool repaid;
    }

    Counters.Counter private _loanIdCounter;
    mapping(uint256 => Loan) public loans;
    mapping(address => uint256[]) public borrowerLoans;

    event LoanCreated(
        uint256 indexed loanId,
        address indexed borrower,
        address indexed nftContract,
        uint256 nftId,
        uint256 loanAmount,
        uint256 interestRate,
        uint256 duration
    );
    event LoanFunded(uint256 indexed loanId, address indexed lender);
    event LoanRepaid(uint256 indexed loanId);

    function createLoan(
        address nftContract,
        uint256 nftId,
        uint256 loanAmount,
        uint256 interestRate,
        uint256 duration
    ) external nonReentrant {
        require(loanAmount > 0, "Loan amount must be greater than zero");
        require(duration > 0, "Loan duration must be greater than zero");

        IERC721 nft = IERC721(nftContract);
        require(
            nft.ownerOf(nftId) == msg.sender,
            "Caller must own the NFT"
        );
        require(
            nft.isApprovedForAll(msg.sender, address(this)) ||
                nft.getApproved(nftId) == address(this),
            "Contract must be approved to transfer NFT"
        );

        nft.transferFrom(msg.sender, address(this), nftId);

        uint256 loanId = _loanIdCounter.current();
        _loanIdCounter.increment();

        loans[loanId] = Loan({
            borrower: msg.sender,
            lender: address(0),
            nftId: nftId,
            nftContract: nftContract,
            loanAmount: loanAmount,
            interestRate: interestRate,
            duration: duration,
            startTime: 0,
            repaid: false
        });

        borrowerLoans[msg.sender].push(loanId);

        emit LoanCreated(
            loanId,
            msg.sender,
            nftContract,
            nftId,
            loanAmount,
            interestRate,
            duration
        );
    }

    function fundLoan(uint256 loanId) external payable nonReentrant {
        Loan storage loan = loans[loanId];

        require(loan.startTime == 0, "Loan already funded");
        require(msg.value == loan.loanAmount, "Incorrect loan amount sent");

        loan.lender = msg.sender;
        loan.startTime = block.timestamp;

        payable(loan.borrower).transfer(loan.loanAmount);

        emit LoanFunded(loanId, msg.sender);
    }

    function repayLoan(uint256 loanId) external payable nonReentrant {
        Loan storage loan = loans[loanId];

        require(loan.lender != address(0), "Loan not yet funded");
        require(!loan.repaid, "Loan already repaid");
        require(
            msg.sender == loan.borrower,
            "Only the borrower can repay the loan"
        );

        uint256 repaymentAmount = loan.loanAmount +
            (loan.loanAmount * loan.interestRate) /
            100;
        require(msg.value == repaymentAmount, "Incorrect repayment amount");
        require(
            block.timestamp <= loan.startTime + loan.duration,
            "Loan duration exceeded"
        );

        loan.repaid = true;

        IERC721(loan.nftContract).transferFrom(
            address(this),
            loan.borrower,
            loan.nftId
        );
        payable(loan.lender).transfer(repaymentAmount);

        emit LoanRepaid(loanId);
    }

    function liquidateLoan(uint256 loanId) external nonReentrant {
        Loan storage loan = loans[loanId];

        require(loan.lender != address(0), "Loan not yet funded");
        require(!loan.repaid, "Loan already repaid");
        require(
            block.timestamp > loan.startTime + loan.duration,
            "Loan duration not yet exceeded"
        );
        require(
            msg.sender == loan.lender,
            "Only the lender can liquidate the loan"
        );

        loan.repaid = true;

        IERC721(loan.nftContract).transferFrom(
            address(this),
            loan.lender,
            loan.nftId
        );
    }
}
