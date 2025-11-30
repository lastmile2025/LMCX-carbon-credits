const solc = require('solc');
const fs = require('fs');
const path = require('path');

const CONTRACTS_DIR = './contracts';
const ARTIFACTS_DIR = './artifacts';
const CACHE_DIR = './cache';
const NODE_MODULES = './node_modules';

// Recursively find all .sol files
function findSolFiles(dir, files = []) {
  const items = fs.readdirSync(dir);
  for (const item of items) {
    const fullPath = path.join(dir, item);
    if (fs.statSync(fullPath).isDirectory()) {
      findSolFiles(fullPath, files);
    } else if (item.endsWith('.sol')) {
      files.push(fullPath);
    }
  }
  return files;
}

// Import resolver for @openzeppelin and other packages
function findImport(importPath) {
  // Handle @openzeppelin imports
  if (importPath.startsWith('@')) {
    const fullPath = path.join(NODE_MODULES, importPath);
    if (fs.existsSync(fullPath)) {
      return { contents: fs.readFileSync(fullPath, 'utf8') };
    }
  }
  
  // Handle local imports
  const localPath = path.join(CONTRACTS_DIR, importPath);
  if (fs.existsSync(localPath)) {
    return { contents: fs.readFileSync(localPath, 'utf8') };
  }
  
  // Try relative to contracts
  const relativePath = path.resolve(CONTRACTS_DIR, importPath);
  if (fs.existsSync(relativePath)) {
    return { contents: fs.readFileSync(relativePath, 'utf8') };
  }
  
  return { error: `File not found: ${importPath}` };
}

// Create directories
fs.mkdirSync(ARTIFACTS_DIR, { recursive: true });
fs.mkdirSync(CACHE_DIR, { recursive: true });

const solFiles = findSolFiles(CONTRACTS_DIR);
console.log(`Found ${solFiles.length} Solidity files`);

// Build sources object
const sources = {};
for (const file of solFiles) {
  const content = fs.readFileSync(file, 'utf8');
  const relativePath = path.relative(CONTRACTS_DIR, file);
  sources[relativePath] = { content };
}

// Compiler input
const input = {
  language: 'Solidity',
  sources,
  settings: {
    optimizer: { enabled: true, runs: 200 },
    evmVersion: 'london',
    viaIR: true,
    outputSelection: {
      '*': {
        '*': ['abi', 'evm.bytecode', 'evm.deployedBytecode', 'metadata']
      }
    }
  }
};

console.log('Compiling...');
const output = JSON.parse(solc.compile(JSON.stringify(input), { import: findImport }));

// Check for errors
if (output.errors) {
  let hasErrors = false;
  for (const error of output.errors) {
    console.log(error.formattedMessage);
    if (error.severity === 'error') hasErrors = true;
  }
  if (hasErrors) {
    process.exit(1);
  }
}

// Write artifacts in Hardhat format
for (const [sourceName, contracts] of Object.entries(output.contracts || {})) {
  for (const [contractName, contract] of Object.entries(contracts)) {
    const artifactDir = path.join(ARTIFACTS_DIR, 'contracts', sourceName);
    fs.mkdirSync(artifactDir, { recursive: true });
    
    const artifact = {
      _format: 'hh-sol-artifact-1',
      contractName,
      sourceName: `contracts/${sourceName}`,
      abi: contract.abi,
      bytecode: contract.evm?.bytecode?.object ? '0x' + contract.evm.bytecode.object : '0x',
      deployedBytecode: contract.evm?.deployedBytecode?.object ? '0x' + contract.evm.deployedBytecode.object : '0x',
      linkReferences: contract.evm?.bytecode?.linkReferences || {},
      deployedLinkReferences: contract.evm?.deployedBytecode?.linkReferences || {}
    };
    
    const artifactPath = path.join(artifactDir, `${contractName}.json`);
    fs.writeFileSync(artifactPath, JSON.stringify(artifact, null, 2));
    console.log(`Written: ${artifactPath}`);
  }
}

console.log('Compilation complete!');
