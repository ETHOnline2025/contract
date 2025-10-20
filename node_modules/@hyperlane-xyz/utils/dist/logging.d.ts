import { LevelWithSilent, Logger, pino } from 'pino';
export declare enum LogLevel {
    Trace = "trace",
    Debug = "debug",
    Info = "info",
    Warn = "warn",
    Error = "error",
    Off = "off"
}
export declare function getLogLevel(): pino.LevelWithSilent;
export declare enum LogFormat {
    Pretty = "pretty",
    JSON = "json"
}
export declare function getLogFormat(): LogFormat;
export declare let rootLogger: Logger<never>;
export declare function getRootLogger(): Logger<never>;
export declare function configureRootLogger(newLogFormat: LogFormat, newLogLevel: LogLevel): Logger<never>;
export declare function setRootLogger(logger: Logger): Logger<never>;
export declare function createHyperlanePinoLogger(logLevel: LevelWithSilent, logFormat: LogFormat): Logger<never>;
export declare function ethersBigNumberSerializer(key: string, value: any): any;
//# sourceMappingURL=logging.d.ts.map