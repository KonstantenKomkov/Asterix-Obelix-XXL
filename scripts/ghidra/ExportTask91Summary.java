// Metadata-only Ghidra export. No bytes, listing, or pseudocode leave the local workspace.
// @category Asterix

import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.FunctionIterator;
import java.io.File;
import java.io.FileInputStream;
import java.io.PrintWriter;
import java.security.MessageDigest;

public class ExportTask91Summary extends GhidraScript {
    private static String hex(byte[] bytes) {
        StringBuilder result = new StringBuilder();
        for (byte value : bytes) result.append(String.format("%02x", value));
        return result.toString();
    }

    private static String sha256(File file) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        try (FileInputStream input = new FileInputStream(file)) {
            byte[] buffer = new byte[1024 * 1024];
            int read;
            while ((read = input.read(buffer)) >= 0) digest.update(buffer, 0, read);
        }
        return hex(digest.digest());
    }

    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length != 1) throw new IllegalArgumentException("expected output path");
        File executable = new File(currentProgram.getExecutablePath());
        long functions = 0;
        FunctionIterator iterator = currentProgram.getFunctionManager().getFunctions(true);
        while (iterator.hasNext()) { iterator.next(); functions++; }
        try (PrintWriter output = new PrintWriter(args[0], "UTF-8")) {
            output.printf(
                "{\"format\":\"%s\",\"functionCount\":%d,\"imageBase\":\"%s\","
                + "\"language\":\"%s\",\"sha256\":\"%s\"}%n",
                currentProgram.getExecutableFormat(), functions,
                currentProgram.getImageBase(), currentProgram.getLanguageID(), sha256(executable));
        }
    }
}
