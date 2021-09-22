const now = async () => {
  let blockNumber = await ethers.provider.getBlockNumber();
  let block = await ethers.provider.getBlock(blockNumber);
  return block.timestamp;
}

const increaseTime = async (seconds) => {
  await ethers.provider.send('evm_increaseTime', [seconds]);
  await ethers.provider.send('evm_mine');
}

const setBlockTime = async (timestamp) => {
  await network.provider.send("evm_setNextBlockTimestamp", [timestamp])
  await network.provider.send("evm_mine")
}

const generateTicketNumbers = (ticketCount) => {
  let ticketNumbers = [];
  for (let i = 0; i < ticketCount; i++) {
    let number = 0;
    for (let digit = 0; digit < 4; digit++) {
      number = number * 100 + (Math.floor(Math.random() * 18) + 1);
    }
    ticketNumbers[i] = number;
  }
  return ticketNumbers;
}

module.exports = {
  now,
  increaseTime,
  setBlockTime,
  generateTicketNumbers
}